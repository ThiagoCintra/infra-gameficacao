# 🔴 Redis

O Redis é utilizado pelo **LoginService** para armazenar sessões de usuário após o login.

## Configuração

| Parâmetro | Valor padrão |
|-----------|-------------|
| Host | `redis` (Docker) / `localhost` (local) |
| Porta | `6379` |
| Imagem Docker | `redis:7-alpine` |
| Timeout de conexão | `2000ms` |
| Pool max-active | `8` |

---

## Acessar o Redis CLI

```bash
# Dentro do container Docker
docker exec -it redis redis-cli

# Ou diretamente na porta local
redis-cli -h localhost -p 6379
```

---

## Comandos Úteis

```bash
# Verificar se o Redis está respondendo
redis-cli ping
# Resposta esperada: PONG

# Listar todas as chaves armazenadas
keys *

# Listar apenas chaves de sessão
keys session:*

# Obter o valor de uma chave de sessão
get session:<sessionId>

# Verificar o TTL (tempo de vida) de uma chave em segundos
ttl session:<sessionId>

# Verificar o tipo de uma chave
type session:<sessionId>

# Obter informações do servidor Redis
info server

# Verificar uso de memória
info memory

# Contar total de chaves
dbsize
```

---

## Gerenciamento de Cache

```bash
# Remover uma chave específica
del session:<sessionId>

# Limpar TODO o cache (⚠️ cuidado em produção!)
FLUSHALL

# Limpar apenas o banco de dados atual
FLUSHDB
```

---

## Monitoramento em Tempo Real

```bash
# Monitorar todos os comandos executados (modo debug)
redis-cli monitor

# Estatísticas em tempo real
redis-cli --stat
```

---

## Estrutura das Sessões

As sessões armazenadas pelo LoginService possuem a seguinte estrutura aproximada:

```
Chave:  session:<sessionId>
Valor:  { userId, username, channel, contractado, ... }
TTL:    Configurado via JWT_EXPIRATION (padrão: 86400000ms = 24h)
```

---

## Healthcheck

```bash
# Verificar saúde do container Redis
docker inspect redis --format='{{.State.Health.Status}}'

# Health check manual
docker exec redis redis-cli ping
```
