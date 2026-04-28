# ▶️ Execução

## Subir Todos os Serviços

```bash
# A partir do diretório que contém docker-compose-full.yml
docker-compose -f docker-compose-full.yml up -d
```

> Aguarde alguns segundos após o comando. Os health checks garantem que Redis, MongoDB e LocalStack estejam prontos antes de inicializar os serviços Java.

---

## Subir um Serviço Específico

```bash
# Apenas o LoginService (e suas dependências: Redis)
docker-compose -f docker-compose-full.yml up -d login-service

# Apenas o TransactionService (e suas dependências: login-service, localstack)
docker-compose -f docker-compose-full.yml up -d transaction-service

# Apenas o GameService (e suas dependências: mongo, localstack)
docker-compose -f docker-compose-full.yml up -d game-service
```

---

## Verificar Status dos Containers

```bash
docker-compose -f docker-compose-full.yml ps
```

Saída esperada quando todos os serviços estão saudáveis:

```
NAME                   IMAGE               STATUS
login-service          ...                 Up (healthy)
transaction-service    ...                 Up
game-service           ...                 Up
redis                  redis:7-alpine      Up (healthy)
mongo                  mongo:6.0           Up (healthy)
localstack             localstack/...      Up (healthy)
```

---

## Ver Logs

```bash
# Logs de todos os serviços (seguir em tempo real)
docker-compose -f docker-compose-full.yml logs -f

# Logs de um serviço específico
docker-compose -f docker-compose-full.yml logs -f login-service
docker-compose -f docker-compose-full.yml logs -f transaction-service
docker-compose -f docker-compose-full.yml logs -f game-service

# Últimas 100 linhas de um serviço
docker-compose -f docker-compose-full.yml logs --tail=100 game-service
```

---

## Parar os Serviços

```bash
# Parar todos (mantém os volumes/dados)
docker-compose -f docker-compose-full.yml stop

# Parar e remover containers (mantém volumes)
docker-compose -f docker-compose-full.yml down

# Parar, remover containers E volumes (limpa todos os dados)
docker-compose -f docker-compose-full.yml down -v
```

---

## Reiniciar um Serviço

```bash
# Reiniciar o Redis
docker-compose -f docker-compose-full.yml restart redis

# Reiniciar o LoginService
docker-compose -f docker-compose-full.yml restart login-service
```

---

## Rebuild (após alterar código-fonte)

```bash
# Rebuild e subir um serviço específico
docker-compose -f docker-compose-full.yml up -d --build login-service

# Rebuild e subir todos os serviços
docker-compose -f docker-compose-full.yml up -d --build
```

---

## Verificar Health Check dos Serviços

```bash
# LoginService
curl -s http://localhost:8081/api/v1/actuator/health | python3 -m json.tool

# TransactionService
curl -s http://localhost:8080/actuator/health | python3 -m json.tool

# GameService
curl -s http://localhost:8082/actuator/health | python3 -m json.tool

# Redis
docker exec redis redis-cli ping

# MongoDB
docker exec mongo mongosh --eval "db.runCommand({ping: 1})"

# LocalStack
curl -s http://localhost:4566/_localstack/health | python3 -m json.tool
```
