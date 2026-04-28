# 🔧 Troubleshooting

## Erros Comuns e Soluções

| Erro | Causa Provável | Solução |
|------|---------------|---------|
| `JWT signature does not match spec` | Chave JWT diferente entre serviços | Verificar que `JWT_SECRET` é **idêntico** em LoginService, TransactionService e GameService no `docker-compose-full.yml` |
| `Connection refused: redis:6379` | Redis não iniciou ou não está saudável | `docker-compose -f docker-compose-full.yml restart redis` e aguardar health check |
| `QueueDoesNotExist` | Fila SQS não foi criada no LocalStack | Criar manualmente: `awslocal sqs create-queue --queue-name transactions.fifo --attributes '{"FifoQueue":"true"}'` |
| `Channel 'null' not allowed` | Header `User-Agent` ausente ou falta campo `channel` no token | Verificar resposta do `/me` — o campo `channel` deve estar presente no token |
| `Contract service required` (403) | Usuário não realizou a contratação | Executar `POST /api/v1/contract` com o token antes de criar transações |
| `401 Unauthorized` ao chamar `/transactions` | Token JWT ausente, expirado ou inválido | Realizar novo login e usar o token retornado |
| `LoginService unavailable` (Circuit Breaker aberto) | TransactionService não consegue atingir o LoginService | Verificar se login-service está rodando: `docker-compose -f docker-compose-full.yml ps` |
| Container reinicia em loop | Dependência não saudável | Verificar logs: `docker-compose -f docker-compose-full.yml logs <service>` |
| `MongoTimeoutException` | MongoDB não iniciou corretamente | `docker-compose -f docker-compose-full.yml restart mongo` e aguardar health check |
| Porta já em uso | Outro processo usando a mesma porta | Parar o processo conflitante: `lsof -i :<porta>` e `kill <PID>` |

---

## Diagnóstico Geral

```bash
# 1. Verificar status de todos os containers
docker-compose -f docker-compose-full.yml ps

# 2. Ver logs do serviço com problema
docker-compose -f docker-compose-full.yml logs --tail=50 <nome-do-servico>

# 3. Verificar conectividade entre containers
docker exec login-service curl -s http://redis:6379
docker exec transaction-service curl -s http://login-service:8081/api/v1/actuator/health
docker exec game-service curl -s http://localstack:4566/_localstack/health
```

---

## Problema: LoginService não sobe

```bash
# Verificar se o Redis está saudável
docker exec redis redis-cli ping

# Ver logs do LoginService
docker-compose -f docker-compose-full.yml logs login-service

# Forçar rebuild
docker-compose -f docker-compose-full.yml up -d --build login-service
```

---

## Problema: TransactionService retorna 503

O TransactionService possui Circuit Breaker configurado. Se o LoginService estiver indisponível:

```bash
# Verificar estado do circuit breaker
curl -s http://localhost:8080/actuator/health | python3 -m json.tool

# Reiniciar o LoginService para resetar o circuit breaker
docker-compose -f docker-compose-full.yml restart login-service
```

---

## Problema: GameService não processa mensagens

```bash
# Verificar se a fila existe
awslocal sqs list-queues

# Verificar se há mensagens na fila
awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/transactions.fifo \
  --attribute-names ApproximateNumberOfMessages

# Ver logs do GameService
docker-compose -f docker-compose-full.yml logs -f game-service
```

---

## Problema: Dados inconsistentes no MongoDB

```bash
# Acessar o MongoDB e verificar os dados
docker exec -it mongo mongosh game_db

# Verificar eventos processados
db.game_events.find().sort({processedAt: -1}).limit(5)
db.processed_events.countDocuments()
```

---

## Limpeza Completa (Reset do Ambiente)

```bash
# Parar tudo e remover volumes
docker-compose -f docker-compose-full.yml down -v

# Subir novamente do zero
docker-compose -f docker-compose-full.yml up -d --build
```
