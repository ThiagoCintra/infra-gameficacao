# 🌐 Endpoints

> Todos os endpoints protegidos exigem o header `Authorization: Bearer <token>` obtido no endpoint de login.

---

## LoginService — `http://localhost:8081`

> Contexto base: `/api/v1`

| Método | Endpoint | Auth | Descrição |
|--------|----------|------|-----------|
| `POST` | `/api/v1/auth/login` | ❌ Não | Autenticar usuário e obter token JWT |
| `GET` | `/api/v1/auth/me` | ✅ Bearer | Retornar dados da sessão do usuário autenticado |
| `POST` | `/api/v1/contract` | ✅ Bearer | Contratar o serviço de transações para o usuário |
| `GET` | `/api/v1/actuator/health` | ❌ Não | Health check do LoginService |

### Corpo das Requisições

#### `POST /api/v1/auth/login`
```json
{
  "username": "Thiago",
  "password": "231299"
}
```

#### Resposta de sucesso `POST /api/v1/auth/login`
```json
{
  "token": "<jwt-token>"
}
```

---

## TransactionService — `http://localhost:8080`

| Método | Endpoint | Auth | Headers Adicionais | Descrição |
|--------|----------|------|--------------------|-----------|
| `POST` | `/transactions` | ✅ Bearer | `X-Idempotency-Key: <uuid>` | Criar uma nova transação financeira |
| `GET` | `/actuator/health` | ❌ Não | — | Health check do TransactionService |
| `GET` | `/actuator/info` | ❌ Não | — | Informações da aplicação |
| `GET` | `/actuator/metrics` | ❌ Não | — | Métricas da aplicação |

### Corpo das Requisições

#### `POST /transactions`
```json
{
  "type": "DEPOSITO",
  "amount": 100.50
}
```

> **Tipos disponíveis para `type`:** Verificar enum `TransactionType` no código do TransactionService.

#### Resposta de sucesso `POST /transactions` — HTTP 202 Accepted
```json
{
  "transactionId": "<uuid>"
}
```

> ⚠️ **Idempotência:** O header `X-Idempotency-Key` evita duplicidade de transações. Use um UUID único por requisição (`uuidgen` no Linux/macOS).

---

## GameService — `http://localhost:8082`

> O GameService não expõe endpoints REST de negócio — ele consome eventos SQS de forma assíncrona. Os endpoints disponíveis são apenas de monitoramento.

| Método | Endpoint | Auth | Descrição |
|--------|----------|------|-----------|
| `GET` | `/actuator/health` | ❌ Não | Health check do GameService |
| `GET` | `/actuator/info` | ❌ Não | Informações da aplicação |
| `GET` | `/actuator/metrics` | ❌ Não | Métricas da aplicação |

---

## Resumo Geral

| Serviço | Método | Endpoint | Auth | Descrição |
|---------|--------|----------|------|-----------|
| Login | `POST` | `/api/v1/auth/login` | ❌ | Autenticar usuário |
| Login | `GET` | `/api/v1/auth/me` | ✅ Bearer | Dados do usuário autenticado |
| Login | `POST` | `/api/v1/contract` | ✅ Bearer | Contratar serviço |
| Login | `GET` | `/api/v1/actuator/health` | ❌ | Health check |
| Transaction | `POST` | `/transactions` | ✅ Bearer | Criar transação (+ X-Idempotency-Key) |
| Transaction | `GET` | `/actuator/health` | ❌ | Health check |
| Game | `GET` | `/actuator/health` | ❌ | Health check |
