# 🧪 Testes

## Fluxo Completo via curl

### 1. Login — Obter Token JWT

```bash
TOKEN=$(curl -s -X POST http://localhost:8081/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"Thiago","password":"231299"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

echo "Token: $TOKEN"
```

---

### 2. Me — Verificar Dados do Usuário

```bash
curl -s -X GET http://localhost:8081/api/v1/auth/me \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

---

### 3. Contract — Contratar o Serviço

```bash
curl -s -X POST http://localhost:8081/api/v1/contract \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

---

### 4. Transaction — Criar uma Transação

```bash
curl -s -X POST http://localhost:8080/transactions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  -d '{"type":"DEPOSITO","amount":100.50}' | python3 -m json.tool
```

---

### 5. Health Checks

```bash
# LoginService
curl -s http://localhost:8081/api/v1/actuator/health | python3 -m json.tool

# TransactionService
curl -s http://localhost:8080/actuator/health | python3 -m json.tool

# GameService
curl -s http://localhost:8082/actuator/health | python3 -m json.tool
```

---

## Script de Teste Completo

```bash
#!/bin/bash
set -e

BASE_LOGIN="http://localhost:8081/api/v1"
BASE_TRANSACTION="http://localhost:8080"

echo "=== 1. Login ==="
RESPONSE=$(curl -s -X POST "$BASE_LOGIN/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"Thiago","password":"231299"}')
echo "$RESPONSE"
TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

echo ""
echo "=== 2. Me ==="
curl -s -X GET "$BASE_LOGIN/auth/me" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo ""
echo "=== 3. Contract ==="
curl -s -X POST "$BASE_LOGIN/contract" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo ""
echo "=== 4. Transaction ==="
IDEMPOTENCY_KEY=$(uuidgen || python3 -c "import uuid; print(uuid.uuid4())")
curl -s -X POST "$BASE_TRANSACTION/transactions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Idempotency-Key: $IDEMPOTENCY_KEY" \
  -d '{"type":"DEPOSITO","amount":100.50}' | python3 -m json.tool

echo ""
echo "=== Concluído! ==="
```

---

## Verificação no MongoDB após Transação

```bash
# Verificar se o evento foi processado pelo GameService
docker exec -it mongo mongosh game_db --eval "db.game_events.find().sort({processedAt:-1}).limit(3).pretty()"
```

---

## Importar Collection Postman

1. Abra o **Postman**
2. Clique em **Import**
3. Selecione o arquivo [`postman-collection.json`](postman-collection.json)
4. A collection **"Itaú Microsserviços"** será importada com todas as requisições pré-configuradas
5. Configure a variável de ambiente `TOKEN` após realizar o login

---

## Variáveis de Ambiente Postman Sugeridas

| Variável | Valor Inicial |
|----------|--------------|
| `base_login` | `http://localhost:8081/api/v1` |
| `base_transaction` | `http://localhost:8080` |
| `base_game` | `http://localhost:8082` |
| `TOKEN` | _(preencher após login)_ |
