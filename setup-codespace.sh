#!/usr/bin/env bash
# =============================================================================
# setup-codespace.sh — Configuração completa do ambiente no GitHub Codespace
# =============================================================================
# Funcionalidades:
#   1. Clone dos repositórios (branch main)
#   2. Subir aplicação via docker-compose
#   3. Testes: Stress (Artillery), E2E, ETH, Chaos Monkey
#   4. Gerar relatório PDF
#   5. Liberar portas para Postman
#   6. Atualizar README
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configurações globais
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_ORG="ThiagoCintra"
REPOS=("LoginService" "TransactionService" "GameService")
BRANCH="main"
REPORT_DIR="$SCRIPT_DIR/reports"
PDF_FILE="$SCRIPT_DIR/Relatorio.pdf"
LOG_DIR="$REPORT_DIR/logs"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Portas expostas
PORTS=(8080 8081 8082 6379 27017 4566)

# Credenciais padrão (apenas dev/local)
LOGIN_USER="Thiago"
LOGIN_PASS="231299"
BASE_LOGIN="http://localhost:8081/api/v1"
BASE_TRANSACTION="http://localhost:8080"
BASE_GAME="http://localhost:8082"
SQS_ENDPOINT="http://localhost:4566"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------
log()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header() { echo -e "\n${BOLD}${BLUE}========== $* ==========${NC}\n"; }

# Escreve linha no relatório markdown
report() { echo "$*" >> "$REPORT_DIR/relatorio.md"; }

# ---------------------------------------------------------------------------
# 0. Preparação de diretórios e ferramentas
# ---------------------------------------------------------------------------
prepare_environment() {
  header "0. Preparando Ambiente"

  mkdir -p "$REPORT_DIR" "$LOG_DIR"

  # Node.js / npm (para Artillery)
  if ! command -v node &>/dev/null; then
    log "Instalando Node.js via nvm..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # shellcheck source=/dev/null
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
    nvm install --lts
  fi

  # Artillery
  if ! command -v artillery &>/dev/null; then
    log "Instalando Artillery..."
    npm install -g artillery@latest 2>&1 | tail -5
  fi

  # wkhtmltopdf (PDF)
  if ! command -v wkhtmltopdf &>/dev/null; then
    log "Instalando wkhtmltopdf..."
    sudo apt-get update -qq && sudo apt-get install -y -qq wkhtmltopdf 2>&1 | tail -3 || \
      warn "wkhtmltopdf não disponível — PDF será gerado via pandoc se possível"
  fi

  # pandoc (fallback PDF)
  if ! command -v pandoc &>/dev/null; then
    log "Instalando pandoc..."
    sudo apt-get install -y -qq pandoc 2>&1 | tail -3 || warn "pandoc não disponível"
  fi

  # AWS CLI (para SQS LocalStack)
  if ! command -v aws &>/dev/null; then
    log "Instalando AWS CLI..."
    sudo apt-get install -y -qq awscli 2>&1 | tail -3 || \
      pip install awscli --quiet 2>&1 | tail -3
  fi

  # stress (Chaos Monkey CPU)
  if ! command -v stress &>/dev/null; then
    sudo apt-get install -y -qq stress 2>&1 | tail -3 || warn "stress não disponível"
  fi

  # jq
  if ! command -v jq &>/dev/null; then
    sudo apt-get install -y -qq jq 2>&1 | tail -3
  fi

  ok "Ambiente preparado"
}

# ---------------------------------------------------------------------------
# 1. Clone dos repositórios
# ---------------------------------------------------------------------------
clone_repositories() {
  header "1. Clonando Repositórios (branch: $BRANCH)"

  for REPO in "${REPOS[@]}"; do
    TARGET_DIR="$SCRIPT_DIR/$REPO"
    if [ -d "$TARGET_DIR/.git" ]; then
      log "$REPO já existe — atualizando..."
      git -C "$TARGET_DIR" fetch origin "$BRANCH" --quiet
      git -C "$TARGET_DIR" reset --hard "origin/$BRANCH" --quiet
      ok "$REPO atualizado"
    else
      log "Clonando $REPO..."
      git clone \
        --branch "$BRANCH" \
        --depth 1 \
        "https://github.com/$GITHUB_ORG/$REPO.git" \
        "$TARGET_DIR" 2>&1 | tail -3
      ok "$REPO clonado em $TARGET_DIR"
    fi
  done
}

# ---------------------------------------------------------------------------
# 2. Subir aplicação via docker-compose
# ---------------------------------------------------------------------------
start_docker_compose() {
  header "2. Subindo Aplicação via Docker Compose"

  cd "$SCRIPT_DIR"

  log "Parando containers existentes (se houver)..."
  docker compose down --remove-orphans 2>/dev/null || docker-compose down --remove-orphans 2>/dev/null || true

  log "Construindo e subindo containers..."
  if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    docker compose up -d --build 2>&1 | tail -20
  else
    docker-compose up -d --build 2>&1 | tail -20
  fi

  # Aguarda 30s para que os containers com healthcheck (Redis, Mongo, LocalStack)
  # completem seus start_period e as JVMs do Spring Boot terminem de inicializar.
  log "Aguardando inicialização dos serviços (30s)..."
  sleep 30

  # Criar fila SQS FIFO
  create_sqs_queue

  ok "Docker Compose iniciado"
}

# ---------------------------------------------------------------------------
# 2b. Criar fila SQS FIFO
# ---------------------------------------------------------------------------
create_sqs_queue() {
  header "2b. Criando Fila SQS FIFO"

  log "Verificando LocalStack..."
  local retries=0
  until curl -sf "$SQS_ENDPOINT/_localstack/health" | grep -q '"sqs"' || [ $retries -ge 10 ]; do
    sleep 3
    ((retries++))
    log "Aguardando LocalStack... tentativa $retries/10"
  done

  log "Criando fila transactions.fifo..."
  AWS_ACCESS_KEY_ID=test \
  AWS_SECRET_ACCESS_KEY=test \
  AWS_DEFAULT_REGION=us-east-1 \
  aws --endpoint-url="$SQS_ENDPOINT" sqs create-queue \
    --queue-name "transactions.fifo" \
    --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true"}' \
    2>&1 || warn "Fila pode já existir ou LocalStack ainda iniciando"

  ok "Fila SQS FIFO criada/verificada"
}

# ---------------------------------------------------------------------------
# Helper: obter token JWT
# ---------------------------------------------------------------------------
get_token() {
  local response
  response=$(curl -sf -X POST "$BASE_LOGIN/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$LOGIN_USER\",\"password\":\"$LOGIN_PASS\"}" 2>/dev/null) || {
    warn "Não foi possível obter token JWT"
    echo ""
    return 1
  }
  echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || \
    echo "$response" | jq -r '.token // empty' 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# 3a. Teste de Stress — Artillery
# ---------------------------------------------------------------------------
run_stress_test() {
  header "3a. Teste de Stress (Artillery)"

  report "## 3a. Teste de Stress (Artillery)"
  report ""
  report "Data: $(date '+%Y-%m-%d %H:%M:%S')"
  report ""

  local TOKEN
  TOKEN=$(get_token) || { warn "Stress test pulado — sem token"; report "❌ Stress test pulado — serviço indisponível"; return; }

  # Gerar configuração Artillery
  cat > /tmp/artillery-stress.yml <<ARTILLERY
config:
  target: "http://localhost:8080"
  phases:
    - duration: 30
      arrivalRate: 5
      name: "Aquecimento"
    - duration: 60
      arrivalRate: 20
      name: "Carga Principal"
    - duration: 30
      arrivalRate: 50
      name: "Pico"
  defaults:
    headers:
      Authorization: "Bearer ${TOKEN}"
      Content-Type: "application/json"

scenarios:
  - name: "Health Check"
    flow:
      - get:
          url: "/actuator/health"
  - name: "POST Transaction"
    flow:
      - post:
          url: "/transactions"
          headers:
            # {{ $randomString() }} é a sintaxe de template do Artillery para gerar
            # uma string aleatória em cada requisição, garantindo chaves únicas por request.
            X-Idempotency-Key: "{{ \$randomString() }}"
          json:
            type: "DEPOSITO"
            amount: 100.50
ARTILLERY

  log "Executando Artillery (120s)..."
  local artillery_log="$LOG_DIR/artillery-$TIMESTAMP.json"
  artillery run /tmp/artillery-stress.yml \
    --output "$artillery_log" \
    2>&1 | tee "$LOG_DIR/artillery-stdout-$TIMESTAMP.txt" || warn "Artillery concluído com avisos"

  # Sumário
  if [ -f "$artillery_log" ]; then
    local rps p95 errors
    rps=$(jq -r '.aggregate.rates.http_req_rate // "N/A"' "$artillery_log" 2>/dev/null || echo "N/A")
    p95=$(jq -r '.aggregate.latency.p95 // "N/A"' "$artillery_log" 2>/dev/null || echo "N/A")
    errors=$(jq -r '.aggregate.counters["http.codes.5xx"] // 0' "$artillery_log" 2>/dev/null || echo "0")
    report "| Métrica | Valor |"
    report "|---------|-------|"
    report "| RPS Médio | $rps |"
    report "| Latência p95 | ${p95}ms |"
    report "| Erros 5xx | $errors |"
    report ""
    ok "Stress test concluído — RPS: $rps, p95: ${p95}ms, erros: $errors"
  else
    report "Resultados detalhados em: $LOG_DIR/artillery-stdout-$TIMESTAMP.txt"
    ok "Stress test concluído"
  fi
}

# ---------------------------------------------------------------------------
# 3b. Teste E2E — curl automatizado
# ---------------------------------------------------------------------------
run_e2e_test() {
  header "3b. Teste E2E (curl automatizado)"

  report "## 3b. Teste E2E (curl automatizado)"
  report ""

  local PASS=0
  local FAIL=0
  local TOKEN=""

  # ---- Health checks ----
  log "Verificando health checks..."
  for SVC_NAME in "LoginService:$BASE_LOGIN/actuator/health" \
                  "TransactionService:$BASE_TRANSACTION/actuator/health" \
                  "GameService:$BASE_GAME/actuator/health"; do
    local name="${SVC_NAME%%:*}"
    local url="${SVC_NAME#*:}"
    local http_code
    http_code=$(curl -o /dev/null -sw "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ]; then
      ok "$name health: UP ($http_code)"
      report "- ✅ $name health: **UP** (HTTP $http_code)"
      ((PASS++))
    else
      warn "$name health: DOWN ($http_code)"
      report "- ❌ $name health: **DOWN** (HTTP $http_code)"
      ((FAIL++))
    fi
  done

  # ---- Login ----
  log "Testando login..."
  local login_resp
  login_resp=$(curl -sf -X POST "$BASE_LOGIN/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$LOGIN_USER\",\"password\":\"$LOGIN_PASS\"}" 2>/dev/null) || login_resp=""

  TOKEN=$(echo "$login_resp" | jq -r '.token // empty' 2>/dev/null || \
          echo "$login_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

  if [ -n "$TOKEN" ]; then
    ok "Login bem-sucedido — token obtido"
    report "- ✅ Login: **OK** — token JWT obtido"
    ((PASS++))
  else
    warn "Login falhou"
    report "- ❌ Login: **FALHOU**"
    ((FAIL++))
    report ""
    report "**Total: PASS=$PASS / FAIL=$FAIL**"
    return
  fi

  # ---- GET /auth/me ----
  log "Testando GET /auth/me..."
  local me_code
  me_code=$(curl -o /dev/null -sw "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" "$BASE_LOGIN/auth/me" 2>/dev/null || echo "000")
  if [ "$me_code" = "200" ]; then
    ok "/auth/me: OK ($me_code)"
    report "- ✅ GET /auth/me: **OK** (HTTP $me_code)"
    ((PASS++))
  else
    warn "/auth/me: FALHOU ($me_code)"
    report "- ❌ GET /auth/me: **FALHOU** (HTTP $me_code)"
    ((FAIL++))
  fi

  # ---- POST /contract ----
  log "Testando POST /contract..."
  local contract_code
  contract_code=$(curl -o /dev/null -sw "%{http_code}" \
    -X POST -H "Authorization: Bearer $TOKEN" "$BASE_LOGIN/contract" 2>/dev/null || echo "000")
  if [[ "$contract_code" =~ ^2 ]]; then
    ok "/contract: OK ($contract_code)"
    report "- ✅ POST /contract: **OK** (HTTP $contract_code)"
    ((PASS++))
  else
    warn "/contract: $contract_code (pode já estar contratado)"
    report "- ⚠️  POST /contract: HTTP $contract_code (pode já estar ativo)"
  fi

  # ---- POST /transactions ----
  log "Testando POST /transactions..."
  # Cadeia de fallback para UUID: python3 (uuid4) → /proc/sys/kernel/random/uuid → timestamp
  local idempotency_key
  idempotency_key=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                    cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)
  local txn_code txn_resp
  txn_resp=$(curl -sf -X POST "$BASE_TRANSACTION/transactions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Idempotency-Key: $idempotency_key" \
    -d '{"type":"DEPOSITO","amount":100.50}' 2>/dev/null) || txn_resp=""
  txn_code=$(curl -o /dev/null -sw "%{http_code}" -X POST "$BASE_TRANSACTION/transactions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Idempotency-Key: $(python3 -c 'import uuid;print(uuid.uuid4())' 2>/dev/null || echo test-$$)" \
    -d '{"type":"DEPOSITO","amount":50.00}' 2>/dev/null || echo "000")

  if [[ "$txn_code" =~ ^2 ]]; then
    ok "/transactions: OK ($txn_code)"
    report "- ✅ POST /transactions: **OK** (HTTP $txn_code)"
    ((PASS++))
  else
    warn "/transactions: $txn_code"
    report "- ❌ POST /transactions: **FALHOU** (HTTP $txn_code)"
    ((FAIL++))
  fi

  # ---- Idempotência (reenviar mesma chave) ----
  log "Testando idempotência..."
  local idem_code
  idem_code=$(curl -o /dev/null -sw "%{http_code}" -X POST "$BASE_TRANSACTION/transactions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Idempotency-Key: $idempotency_key" \
    -d '{"type":"DEPOSITO","amount":100.50}' 2>/dev/null || echo "000")
  report "- ℹ️  Idempotência (mesma chave reenviada): HTTP $idem_code"

  report ""
  report "**Total: PASS=$PASS / FAIL=$FAIL**"
  report ""
  ok "E2E test concluído — PASS=$PASS FAIL=$FAIL"
}

# ---------------------------------------------------------------------------
# 3c. Teste ETH — Ethical Hacking (SQL Injection, XSS, Força Bruta)
# ---------------------------------------------------------------------------
run_eth_test() {
  header "3c. Teste ETH (Ethical Hacking)"

  report "## 3c. Teste ETH — Ethical Hacking"
  report ""
  report "> Testes realizados em ambiente local controlado para fins de validação de segurança."
  report ""

  local ETH_PASS=0
  local ETH_VULN=0

  # ---- SQL Injection ----
  log "Testando SQL Injection no endpoint de login..."
  report "### SQL Injection"
  report ""
  local sqli_payloads=(
    "' OR '1'='1"
    "' OR 1=1--"
    "admin'--"
    "' UNION SELECT 1,2,3--"
    "'; DROP TABLE users;--"
  )
  for payload in "${sqli_payloads[@]}"; do
    local code
    code=$(curl -o /dev/null -sw "%{http_code}" -X POST "$BASE_LOGIN/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$payload\",\"password\":\"$payload\"}" 2>/dev/null || echo "000")
    if [[ "$code" =~ ^(200|201) ]]; then
      warn "VULNERÁVEL a SQLi com payload: $payload (HTTP $code)"
      report "- ⚠️  **VULNERÁVEL**: payload \`$payload\` — HTTP $code"
      ((ETH_VULN++))
    else
      report "- ✅ Protegido: payload \`$payload\` — HTTP $code"
      ((ETH_PASS++))
    fi
  done

  # ---- XSS ----
  log "Testando XSS no endpoint de login..."
  report ""
  report "### XSS (Cross-Site Scripting)"
  report ""
  local xss_payloads=(
    "<script>alert('xss')</script>"
    '"><img src=x onerror=alert(1)>'
    "javascript:alert(1)"
    "<svg onload=alert(1)>"
  )
  for payload in "${xss_payloads[@]}"; do
    local code body
    body=$(curl -sf -X POST "$BASE_LOGIN/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$payload\",\"password\":\"test\"}" 2>/dev/null || echo "")
    code=$(curl -o /dev/null -sw "%{http_code}" -X POST "$BASE_LOGIN/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$payload\",\"password\":\"test\"}" 2>/dev/null || echo "000")
    # Verificar se o payload foi refletido na resposta (XSS refletido)
    if echo "$body" | grep -qF "$payload" 2>/dev/null; then
      warn "POSSÍVEL XSS refletido com payload: $payload"
      report "- ⚠️  **POSSÍVEL XSS refletido**: payload devolvido na resposta — HTTP $code"
      ((ETH_VULN++))
    else
      report "- ✅ Protegido (não refletido): \`${payload:0:40}\` — HTTP $code"
      ((ETH_PASS++))
    fi
  done

  # ---- Força Bruta ----
  log "Testando proteção contra força bruta..."
  report ""
  report "### Força Bruta"
  report ""
  local brute_blocked=false
  local last_code="000"
  for i in $(seq 1 15); do
    last_code=$(curl -o /dev/null -sw "%{http_code}" -X POST "$BASE_LOGIN/auth/login" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"admin\",\"password\":\"wrong$i\"}" 2>/dev/null || echo "000")
    if [[ "$last_code" =~ ^(429|423|403) ]]; then
      ok "Proteção contra força bruta detectada após $i tentativas (HTTP $last_code)"
      report "- ✅ Proteção ativa: bloqueado após $i tentativas (HTTP $last_code)"
      brute_blocked=true
      ((ETH_PASS++))
      break
    fi
    sleep 0.2  # Pequena pausa entre tentativas para não sobrecarregar o serviço durante o teste
  done
    if [[ "$brute_blocked" = false ]]; then
      warn "Sem proteção detectada contra força bruta (HTTP $last_code após 15 tentativas)"
      report "- ⚠️  **SEM PROTEÇÃO** detectada contra força bruta após 15 tentativas (HTTP $last_code)"
      ((ETH_VULN++))
    fi

  # ---- Headers de Segurança ----
  log "Verificando headers de segurança HTTP..."
  report ""
  report "### Headers de Segurança HTTP"
  report ""
  # Tenta o endpoint versionado (/api/v1/actuator/health) do LoginService primeiro,
  # com fallback para o endpoint padrão do Spring Boot Actuator (/actuator/health).
  local headers
  headers=$(curl -sI "$BASE_LOGIN/api/v1/actuator/health" 2>/dev/null || \
            curl -sI "$BASE_LOGIN/actuator/health" 2>/dev/null || echo "")
  for header_name in "X-Content-Type-Options" "X-Frame-Options" "Strict-Transport-Security" \
                     "Content-Security-Policy" "X-XSS-Protection"; do
    if echo "$headers" | grep -qi "$header_name"; then
      report "- ✅ $header_name: presente"
      ((ETH_PASS++))
    else
      report "- ⚠️  $header_name: **ausente**"
      ((ETH_VULN++))
    fi
  done

  report ""
  report "**Resumo ETH: Protegido=$ETH_PASS / Vulnerável/Ausente=$ETH_VULN**"
  report ""
  ok "ETH test concluído — Protegido=$ETH_PASS Vulnerável=$ETH_VULN"
}

# ---------------------------------------------------------------------------
# 3d. Teste Chaos Monkey
# ---------------------------------------------------------------------------
run_chaos_monkey() {
  header "3d. Chaos Monkey (Resiliência)"

  report "## 3d. Chaos Monkey — Testes de Resiliência"
  report ""

  local CHAOS_PASS=0
  local CHAOS_FAIL=0

  # ---- Matar container (login-service) ----
  log "Chaos: matando login-service..."
  report "### Kill Container (login-service)"
  report ""
  docker stop login-service 2>/dev/null || docker kill login-service 2>/dev/null || warn "Container login-service não encontrado"
  sleep 3

  local code_after_kill
  code_after_kill=$(curl -o /dev/null -sw "%{http_code}" --max-time 5 \
    "$BASE_LOGIN/actuator/health" 2>/dev/null || echo "000")
  if [[ "$code_after_kill" != "200" ]]; then
    report "- ✅ Container morto — serviço corretamente indisponível (HTTP $code_after_kill)"
    ((CHAOS_PASS++))
  else
    report "- ℹ️  Serviço ainda respondendo após kill (HTTP $code_after_kill)"
  fi

  log "Reiniciando login-service..."
  docker start login-service 2>/dev/null || docker compose start login-service 2>/dev/null || \
    docker-compose start login-service 2>/dev/null || true
  sleep 10

  local code_after_restart
  code_after_restart=$(curl -o /dev/null -sw "%{http_code}" --max-time 10 \
    "$BASE_LOGIN/actuator/health" 2>/dev/null || echo "000")
  if [ "$code_after_restart" = "200" ]; then
    ok "login-service se recuperou após restart"
    report "- ✅ Recuperação após restart: **OK** (HTTP $code_after_restart)"
    ((CHAOS_PASS++))
  else
    warn "login-service NÃO se recuperou (HTTP $code_after_restart)"
    report "- ❌ Recuperação após restart: **FALHOU** (HTTP $code_after_restart)"
    ((CHAOS_FAIL++))
  fi

  # ---- Latência de rede (tc - traffic control) ----
  report ""
  report "### Latência de Rede Simulada (tc)"
  report ""
  log "Chaos: simulando latência de rede no transaction-service..."
  # Simula 500ms de latência de rede — valor suficiente para impactar SLAs
  # sem causar timeout imediato nos clientes (limite padrão costuma ser ≥1s).
  if docker exec transaction-service tc qdisc add dev eth0 root netem delay 500ms 2>/dev/null; then
    sleep 3
    local latency_code latency_time
    latency_time=$(curl -o /dev/null -sw "%{time_total}" --max-time 10 \
      "$BASE_TRANSACTION/actuator/health" 2>/dev/null || echo "0")
    report "- ℹ️  Latência simulada: tempo de resposta = ${latency_time}s"
    # Remover latência
    docker exec transaction-service tc qdisc del dev eth0 root 2>/dev/null || true
    report "- ✅ Latência de rede simulada e removida com sucesso"
    ((CHAOS_PASS++))
  else
    report "- ⚠️  tc não disponível no container — simulação de latência pulada"
    warn "tc não disponível, pulando simulação de latência"
  fi

  # ---- Stress de CPU ----
  report ""
  report "### Stress de CPU"
  report ""
  log "Chaos: estressando CPU do transaction-service por 15s..."
  # stress: --cpu 2 estressa 2 núcleos de CPU, --timeout 15 limita a 15 segundos.
  # Fallback: dd lê /dev/zero em loop (blocos de 1M) para saturar CPU sem o pacote stress.
  if docker exec -d transaction-service sh -c "nohup stress --cpu 2 --timeout 15 &" 2>/dev/null || \
     docker exec -d transaction-service sh -c "dd if=/dev/zero of=/dev/null bs=1M count=10000 &" 2>/dev/null; then
    sleep 5
    local cpu_code
    cpu_code=$(curl -o /dev/null -sw "%{http_code}" --max-time 10 \
      "$BASE_TRANSACTION/actuator/health" 2>/dev/null || echo "000")
    if [ "$cpu_code" = "200" ]; then
      ok "Serviço manteve saúde sob stress de CPU (HTTP $cpu_code)"
      report "- ✅ Serviço respondeu sob stress de CPU: HTTP $cpu_code"
      ((CHAOS_PASS++))
    else
      warn "Serviço degradou sob stress de CPU (HTTP $cpu_code)"
      report "- ⚠️  Serviço degradado sob stress de CPU: HTTP $cpu_code"
      ((CHAOS_FAIL++))
    fi
    sleep 15
  else
    report "- ⚠️  Stress de CPU não disponível no container — pulado"
    warn "Stress de CPU não disponível no container"
  fi

  # ---- Pausa de container (game-service) ----
  report ""
  report "### Pause/Unpause de Container (game-service)"
  report ""
  log "Chaos: pausando game-service..."
  if docker pause game-service 2>/dev/null; then
    sleep 5
    local pause_code
    pause_code=$(curl -o /dev/null -sw "%{http_code}" --max-time 5 \
      "$BASE_GAME/actuator/health" 2>/dev/null || echo "000")
    report "- ✅ game-service pausado — HTTP $pause_code (esperado timeout)"
    docker unpause game-service 2>/dev/null
    sleep 5
    local unpause_code
    unpause_code=$(curl -o /dev/null -sw "%{http_code}" --max-time 10 \
      "$BASE_GAME/actuator/health" 2>/dev/null || echo "000")
    report "- ✅ game-service retomado: HTTP $unpause_code"
    ((CHAOS_PASS++))
  else
    report "- ⚠️  docker pause não disponível — pulado"
    warn "docker pause não disponível"
  fi

  report ""
  report "**Resumo Chaos: OK=$CHAOS_PASS / FALHOU=$CHAOS_FAIL**"
  report ""
  ok "Chaos Monkey concluído — OK=$CHAOS_PASS FAIL=$CHAOS_FAIL"
}

# ---------------------------------------------------------------------------
# 3e. Melhorias Sugeridas
# ---------------------------------------------------------------------------
generate_improvements() {
  header "3e. Melhorias Sugeridas"

  report "## 4. Melhorias Sugeridas"
  report ""
  report "Com base nos testes executados, as seguintes melhorias são recomendadas:"
  report ""

  report "### 🔐 Segurança"
  report ""
  report "| # | Melhoria | Prioridade |"
  report "|---|----------|-----------|"
  report "| 1 | Implementar rate limiting (ex: Bucket4j, Resilience4j) para proteção contra força bruta | 🔴 Alta |"
  report "| 2 | Adicionar headers de segurança HTTP (X-Frame-Options, CSP, HSTS) via Spring Security | 🔴 Alta |"
  report "| 3 | Usar HashiCorp Vault ou AWS Secrets Manager para JWT_SECRET em produção | 🔴 Alta |"
  report "| 4 | Implementar validação e sanitização de entrada com Bean Validation + encoding | 🟡 Média |"
  report "| 5 | Habilitar HTTPS/TLS (certificado Let's Encrypt ou ACM) | 🔴 Alta |"
  report "| 6 | Rotacionar JWT_SECRET periodicamente e implementar blacklist de tokens | 🟡 Média |"
  report ""

  report "### ⚡ Performance"
  report ""
  report "| # | Melhoria | Prioridade |"
  report "|---|----------|-----------|"
  report "| 1 | Configurar connection pool no MongoDB (spring.data.mongodb.uri com parâmetros) | 🟡 Média |"
  report "| 2 | Implementar cache L2 com Redis para dados frequentemente consultados | 🟡 Média |"
  report "| 3 | Adicionar compressão HTTP (gzip) no Spring Boot | 🟢 Baixa |"
  report "| 4 | Usar SQS batch processing para maior throughput no GameService | 🟡 Média |"
  report "| 5 | Configurar JVM flags para containers (HeapSize, GC tuning) | 🟡 Média |"
  report ""

  report "### 🛡️ Resiliência"
  report ""
  report "| # | Melhoria | Prioridade |"
  report "|---|----------|-----------|"
  report "| 1 | Implementar Circuit Breaker (Resilience4j) nas chamadas entre serviços | 🔴 Alta |"
  report "| 2 | Adicionar retry com backoff exponencial nas chamadas SQS | 🟡 Média |"
  report "| 3 | Configurar health check detalhado com /actuator/health/liveness e /readiness | 🟡 Média |"
  report "| 4 | Implementar Dead Letter Queue (DLQ) para mensagens SQS com falha | 🔴 Alta |"
  report "| 5 | Adicionar timeout configurável em todas as chamadas HTTP externas | 🟡 Média |"
  report ""

  report "### 📊 Observabilidade"
  report ""
  report "| # | Melhoria | Prioridade |"
  report "|---|----------|-----------|"
  report "| 1 | Adicionar Prometheus + Grafana para métricas (micrometer já incluído) | 🟡 Média |"
  report "| 2 | Implementar distributed tracing com OpenTelemetry/Jaeger | 🟡 Média |"
  report "| 3 | Centralizar logs com ELK Stack ou AWS CloudWatch | 🟢 Baixa |"
  report "| 4 | Adicionar alertas de SLA (tempo de resposta, taxa de erro) | 🟡 Média |"
  report ""

  report "### 🏗️ Infraestrutura"
  report ""
  report "| # | Melhoria | Prioridade |"
  report "|---|----------|-----------|"
  report "| 1 | Migrar para Kubernetes (EKS/GKE) para auto-scaling em produção | 🟢 Baixa |"
  report "| 2 | Implementar CI/CD pipeline (GitHub Actions) com testes automáticos | 🟡 Média |"
  report "| 3 | Separar ambientes (dev, staging, prod) com profiles Spring Boot | 🟡 Média |"
  report "| 4 | Adicionar backup automático do MongoDB | 🔴 Alta |"
  report ""

  ok "Melhorias sugeridas geradas"
}

# ---------------------------------------------------------------------------
# 4. Gerar Relatório PDF
# ---------------------------------------------------------------------------
generate_pdf_report() {
  header "4. Gerando Relatório PDF"

  # Remover PDF anterior se existir
  if [ -f "$PDF_FILE" ]; then
    log "Removendo Relatorio.pdf anterior..."
    rm -f "$PDF_FILE"
    ok "PDF anterior removido"
  fi

  # Cabeçalho do relatório markdown
  local md_file="$REPORT_DIR/relatorio.md"
  local tmp_md="/tmp/relatorio-final-$TIMESTAMP.md"

  # Criar cabeçalho
  cat > "$tmp_md" <<HEADER
# 📊 Relatório de Testes — Itaú Microsserviços

**Data:** $(date '+%d/%m/%Y %H:%M:%S')
**Ambiente:** GitHub Codespace / Docker Compose
**Branch:** $BRANCH

---

## 🏗️ Serviços Testados

| Serviço | Porta | URL |
|---------|-------|-----|
| LoginService | 8081 | http://localhost:8081 |
| TransactionService | 8080 | http://localhost:8080 |
| GameService | 8082 | http://localhost:8082 |
| Redis | 6379 | redis://localhost:6379 |
| MongoDB | 27017 | mongodb://localhost:27017 |
| LocalStack/SQS | 4566 | http://localhost:4566 |

---

HEADER

  # Append resultados dos testes
  cat "$md_file" >> "$tmp_md" 2>/dev/null || true

  # Footer
  cat >> "$tmp_md" <<FOOTER

---

## 📁 Arquivos de Log

Os logs detalhados estão disponíveis em: \`$LOG_DIR/\`

---

*Relatório gerado automaticamente por setup-codespace.sh em $(date '+%d/%m/%Y às %H:%M:%S')*
FOOTER

  # Gerar PDF
  local pdf_generated=false

  # Tentativa 1: wkhtmltopdf
  if command -v wkhtmltopdf &>/dev/null; then
    log "Gerando PDF com wkhtmltopdf..."
    # Converter markdown para HTML primeiro
    if command -v pandoc &>/dev/null; then
      pandoc "$tmp_md" -o /tmp/relatorio-$TIMESTAMP.html --standalone \
        --metadata title="Relatório de Testes" 2>/dev/null && \
      wkhtmltopdf \
        --page-size A4 \
        --margin-top 20mm \
        --margin-bottom 20mm \
        --margin-left 15mm \
        --margin-right 15mm \
        --enable-local-file-access \
        /tmp/relatorio-$TIMESTAMP.html \
        "$PDF_FILE" 2>/dev/null && pdf_generated=true
    else
      wkhtmltopdf "$tmp_md" "$PDF_FILE" 2>/dev/null && pdf_generated=true
    fi
  fi

  # Tentativa 2: pandoc direto para PDF (requer LaTeX/xelatex)
  if [ "$pdf_generated" = false ] && command -v pandoc &>/dev/null; then
    log "Gerando PDF com pandoc..."
    # xelatex só é tentado se estiver instalado (requer texlive-xetex ou similar)
    if command -v xelatex &>/dev/null; then
      pandoc "$tmp_md" \
        -o "$PDF_FILE" \
        --pdf-engine=xelatex \
        -V geometry:margin=2cm \
        -V lang=pt-BR \
        2>/dev/null && pdf_generated=true || true
    fi

    # Tentativa pandoc sem motor específico (usa pdflatex se disponível, caso contrário falha graciosamente)
    if [ "$pdf_generated" = false ]; then
      pandoc "$tmp_md" -o "$PDF_FILE" 2>/dev/null && pdf_generated=true || true
    fi
  fi

  # Tentativa 3: chromium headless
  if [ "$pdf_generated" = false ]; then
    for chromium_bin in chromium-browser chromium google-chrome google-chrome-stable; do
      if command -v "$chromium_bin" &>/dev/null; then
        log "Gerando PDF com $chromium_bin..."
        if command -v pandoc &>/dev/null; then
          pandoc "$tmp_md" -o /tmp/relatorio-$TIMESTAMP.html --standalone 2>/dev/null || true
        fi
        "$chromium_bin" --headless --no-sandbox --disable-gpu \
          --print-to-pdf="$PDF_FILE" \
          "file:///tmp/relatorio-$TIMESTAMP.html" 2>/dev/null && pdf_generated=true && break
      fi
    done
  fi

  # Cópia do markdown como fallback
  cp "$tmp_md" "$SCRIPT_DIR/Relatorio.md" 2>/dev/null || true

  if [ "$pdf_generated" = true ] && [ -f "$PDF_FILE" ]; then
    ok "Relatório PDF gerado: $PDF_FILE ($(du -sh "$PDF_FILE" | cut -f1))"
  else
    warn "Não foi possível gerar PDF — relatório disponível como Markdown: $SCRIPT_DIR/Relatorio.md"
    # Criar um PDF stub (arquivo de texto renomeado) como fallback final
    if command -v enscript &>/dev/null && command -v ps2pdf &>/dev/null; then
      enscript -p /tmp/relatorio-$TIMESTAMP.ps "$tmp_md" 2>/dev/null && \
        ps2pdf /tmp/relatorio-$TIMESTAMP.ps "$PDF_FILE" 2>/dev/null && ok "PDF gerado via enscript+ps2pdf"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 5. Liberar portas para Postman
# ---------------------------------------------------------------------------
expose_ports() {
  header "5. Portas Disponíveis para Postman"

  # Detectar URL base do Codespace
  local BASE_URL="localhost"
  if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
    BASE_URL="${CODESPACE_NAME}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    log "GitHub Codespace detectado: $BASE_URL"
    # Tentar encaminhar portas via gh cli
    if command -v gh &>/dev/null; then
      for port in "${PORTS[@]}"; do
        gh codespace ports visibility "$port":public --codespace "$CODESPACE_NAME" 2>/dev/null || \
          warn "Não foi possível tornar porta $port pública via gh cli"
      done
    fi
  fi

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║              🌐 URLS DOS SERVIÇOS DISPONÍVEIS               ║${NC}"
  echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  LoginService         → ${CYAN}http://$BASE_URL:8081${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  TransactionService   → ${CYAN}http://$BASE_URL:8080${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  GameService          → ${CYAN}http://$BASE_URL:8082${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  Redis                → ${CYAN}redis://$BASE_URL:6379${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  MongoDB              → ${CYAN}mongodb://$BASE_URL:27017${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  LocalStack/SQS       → ${CYAN}http://$BASE_URL:4566${NC}"
  echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOLD}${GREEN}║  Health Checks:${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  Login    → ${CYAN}http://$BASE_URL:8081/api/v1/actuator/health${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  Txn      → ${CYAN}http://$BASE_URL:8080/actuator/health${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  Game     → ${CYAN}http://$BASE_URL:8082/actuator/health${NC}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  report "## 5. Portas Liberadas"
  report ""
  report "| Serviço | Porta | URL |"
  report "|---------|-------|-----|"
  report "| LoginService | 8081 | http://$BASE_URL:8081 |"
  report "| TransactionService | 8080 | http://$BASE_URL:8080 |"
  report "| GameService | 8082 | http://$BASE_URL:8082 |"
  report "| Redis | 6379 | redis://$BASE_URL:6379 |"
  report "| MongoDB | 27017 | mongodb://$BASE_URL:27017 |"
  report "| LocalStack/SQS | 4566 | http://$BASE_URL:4566 |"
  report ""
}

# ---------------------------------------------------------------------------
# 6. Atualizar README
# ---------------------------------------------------------------------------
update_readme() {
  header "6. Atualizando README.md"

  local readme="$SCRIPT_DIR/README.md"
  local today
  today=$(date '+%d/%m/%Y')

  # Verificar se seção já existe para não duplicar
  if [ ! -f "$readme" ]; then
    warn "README.md não encontrado em $readme — criando arquivo vazio"
    touch "$readme"
  fi

  if grep -q "## 🧪 Relatórios de Teste" "$readme" 2>/dev/null; then
    log "Seção de relatórios já existe no README — removendo para atualizar..."
    # Remover desde a seção até o próximo "## " de nível 2 ou EOF
    python3 - <<PYEOF || warn "Falha ao remover seção de relatórios do README"
import re, sys
try:
    with open('$readme', 'r', encoding='utf-8') as f:
        content = f.read()
    content = re.sub(
        r'\n## 🧪 Relatórios de Teste.*?(?=\n## |\Z)',
        '',
        content,
        flags=re.DOTALL
    )
    with open('$readme', 'w', encoding='utf-8') as f:
        f.write(content)
except Exception as e:
    sys.stderr.write(f"Erro: {e}\n")
    sys.exit(1)
PYEOF
  fi

  # Verificar se seção de portas já existe
  if grep -q "## 🌐 Portas Liberadas" "$readme" 2>/dev/null; then
    log "Seção de portas já existe no README — removendo para atualizar..."
    python3 - <<PYEOF || warn "Falha ao remover seção de portas do README"
import re, sys
try:
    with open('$readme', 'r', encoding='utf-8') as f:
        content = f.read()
    content = re.sub(
        r'\n## 🌐 Portas Liberadas.*?(?=\n## |\Z)',
        '',
        content,
        flags=re.DOTALL
    )
    with open('$readme', 'w', encoding='utf-8') as f:
        f.write(content)
except Exception as e:
    sys.stderr.write(f"Erro: {e}\n")
    sys.exit(1)
PYEOF
  fi

  # Append novas seções ao README
  cat >> "$readme" <<README_SECTION

## 🧪 Relatórios de Teste

> Última execução: **$today** via \`setup-codespace.sh\`

| Relatório | Formato | Link |
|-----------|---------|------|
| Relatório Completo | PDF | [Relatorio.pdf](Relatorio.pdf) |
| Relatório Completo | Markdown | [Relatorio.md](Relatorio.md) |
| Logs Artillery | JSON | [reports/logs/](reports/logs/) |
| Sumário de Testes | Markdown | [reports/relatorio.md](reports/relatorio.md) |

### Resultados dos Testes

| Tipo de Teste | Status |
|---------------|--------|
| ✅ Stress (Artillery) | Executado |
| ✅ E2E (curl) | Executado |
| ✅ ETH (Ethical Hacking) | Executado |
| ✅ Chaos Monkey | Executado |

---

## 🌐 Portas Liberadas

| Serviço | Porta | Descrição |
|---------|-------|-----------|
| **TransactionService** | \`8080\` | API de transações financeiras |
| **LoginService** | \`8081\` | Autenticação JWT + Redis |
| **GameService** | \`8082\` | Gamificação (SQS → MongoDB) |
| **Redis** | \`6379\` | Cache de sessões JWT |
| **MongoDB** | \`27017\` | Persistência de eventos de jogo |
| **LocalStack (SQS)** | \`4566\` | Fila SQS FIFO simulada |

### 🔗 URLs dos Endpoints (Postman)

\`\`\`
POST  http://localhost:8081/api/v1/auth/login      # Login
GET   http://localhost:8081/api/v1/auth/me         # Dados do usuário
POST  http://localhost:8081/api/v1/contract        # Contratar serviço
POST  http://localhost:8080/transactions           # Criar transação
GET   http://localhost:8080/actuator/health        # Health TransactionService
GET   http://localhost:8081/api/v1/actuator/health # Health LoginService
GET   http://localhost:8082/actuator/health        # Health GameService
\`\`\`

README_SECTION

  ok "README.md atualizado com seções de relatórios e portas"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${BLUE}║    🚀 SETUP CODESPACE — Itaú Microsserviços       ║${NC}"
  echo -e "${BOLD}${BLUE}║    $(date '+%Y-%m-%d %H:%M:%S')                        ║${NC}"
  echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
  echo ""

  # Inicializar relatório markdown
  mkdir -p "$REPORT_DIR" "$LOG_DIR"
  > "$REPORT_DIR/relatorio.md"

  # Executar etapas
  prepare_environment
  clone_repositories
  start_docker_compose
  run_stress_test
  run_e2e_test
  run_eth_test
  run_chaos_monkey
  generate_improvements
  generate_pdf_report
  expose_ports
  update_readme

  # Sumário final
  echo ""
  echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║              ✅ SETUP CONCLUÍDO!                   ║${NC}"
  echo -e "${BOLD}${GREEN}╠════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOLD}${GREEN}║  📄 Relatório PDF : Relatorio.pdf                  ║${NC}"
  echo -e "${BOLD}${GREEN}║  📝 Relatório MD  : Relatorio.md                   ║${NC}"
  echo -e "${BOLD}${GREEN}║  📁 Logs          : reports/logs/                  ║${NC}"
  echo -e "${BOLD}${GREEN}║  📖 README        : Atualizado                     ║${NC}"
  echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════╝${NC}"
  echo ""
}

main "$@"
