# 🍃 MongoDB

O MongoDB é utilizado pelo **GameService** para persistir eventos de gamificação, progresso dos clientes e missões.

## Configuração

| Parâmetro | Valor padrão |
|-----------|-------------|
| Host | `mongo` (Docker) / `localhost` (local) |
| Porta | `27017` |
| Database | `game_db` |
| URI | `mongodb://mongo:27017/game_db` |
| Imagem Docker | `mongo:6.0` |

---

## Acessar o MongoDB Shell

```bash
# Dentro do container Docker
docker exec -it mongo mongosh

# Conectar diretamente ao banco game_db
docker exec -it mongo mongosh game_db
```

---

## Comandos Úteis

```bash
# Listar todos os bancos de dados
show dbs

# Selecionar o banco de dados do GameService
use game_db

# Listar as collections disponíveis
show collections
```

---

## Collections

### `game_events`
Eventos de transação recebidos do SQS e persistidos pelo GameService.

```bash
# Listar todos os eventos
db.game_events.find()

# Eventos de um cliente específico
db.game_events.find({ customerId: "<userId>" })

# Eventos por tipo
db.game_events.find({ type: "DEPOSITO" })

# Último evento inserido
db.game_events.find().sort({ processedAt: -1 }).limit(1)

# Contar total de eventos
db.game_events.countDocuments()
```

Estrutura de um documento `game_events`:
```json
{
  "_id": "<eventId>",
  "customerId": "<userId>",
  "type": "DEPOSITO",
  "amount": 100.50,
  "timestamp": "<ISO-8601>",
  "processedAt": "<ISO-8601>"
}
```

---

### `missions`
Missões disponíveis no sistema de gamificação.

```bash
# Listar todas as missões
db.missions.find()

# Buscar missão por nome
db.missions.find({ name: "<nomeDaMissao>" })
```

---

### `customer_progress`
Progresso de cada cliente nas missões e níveis.

```bash
# Listar progresso de todos os clientes
db.customer_progress.find()

# Progresso de um cliente específico
db.customer_progress.find({ customerId: "<userId>" })
```

---

### `mission_completions`
Registro de missões concluídas pelos clientes.

```bash
db.mission_completions.find()
db.mission_completions.find({ customerId: "<userId>" })
```

---

### `benefit_redemptions`
Registro de benefícios resgatados pelos clientes.

```bash
db.benefit_redemptions.find()
```

---

### `processed_events`
Controle de idempotência — eventos já processados pelo GameService.

```bash
db.processed_events.find()
db.processed_events.find({ eventId: "<eventId>" })
```

---

## Limpeza de Dados (⚠️ cuidado!)

```bash
# Limpar todos os game_events
db.game_events.deleteMany({})

# Limpar progresso de todos os clientes
db.customer_progress.deleteMany({})

# Limpar todo o banco game_db
db.dropDatabase()
```

---

## Indexação

```bash
# Verificar índices de uma collection
db.game_events.getIndexes()
db.customer_progress.getIndexes()
```

---

## Monitoramento

```bash
# Estatísticas do banco
db.stats()

# Estatísticas de uma collection
db.game_events.stats()

# Status do servidor MongoDB
db.serverStatus()
```
