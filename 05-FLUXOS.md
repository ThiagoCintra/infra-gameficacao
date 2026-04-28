# 🔄 Fluxos

## 1. Fluxo de Login

O usuário envia suas credenciais ao LoginService, que valida, cria uma sessão no Redis e retorna um token JWT.

```mermaid
sequenceDiagram
    participant C as Cliente
    participant LS as LoginService :8081
    participant R as Redis :6379

    C->>LS: POST /api/v1/auth/login<br/>{"username":"Thiago","password":"231299"}
    LS->>LS: Valida credenciais (H2 DB)
    LS->>R: Armazena sessão (session:<id>)
    R-->>LS: OK
    LS-->>C: 200 OK {"token": "<jwt>"}

    Note over C,R: Token JWT contém: userId, channel, sessionId
```

---

## 2. Fluxo de Consulta do Usuário (`/me`)

```mermaid
sequenceDiagram
    participant C as Cliente
    participant LS as LoginService :8081
    participant R as Redis :6379

    C->>LS: GET /api/v1/auth/me<br/>Authorization: Bearer <token>
    LS->>LS: Valida assinatura JWT (JWT_SECRET)
    LS->>R: Busca sessão pelo sessionId
    R-->>LS: Dados da sessão
    LS-->>C: 200 OK {userId, username, channel, ...}
```

---

## 3. Fluxo de Contratação (`/contract`)

O usuário precisa contratar o serviço antes de poder realizar transações.

```mermaid
sequenceDiagram
    participant C as Cliente
    participant LS as LoginService :8081
    participant R as Redis :6379

    C->>LS: POST /api/v1/contract<br/>Authorization: Bearer <token>
    LS->>LS: Valida JWT e extrai sessionId
    LS->>R: Atualiza sessão com flag contractado=true
    R-->>LS: OK
    LS-->>C: 200 OK
```

> ⚠️ Sem contratação, o TransactionService retorna `403 Forbidden` com a mensagem `Contract service required`.

---

## 4. Fluxo de Transação (com Idempotência)

```mermaid
sequenceDiagram
    participant C as Cliente
    participant TS as TransactionService :8080
    participant LS as LoginService :8081
    participant SQS as LocalStack SQS :4566

    C->>TS: POST /transactions<br/>Authorization: Bearer <token><br/>X-Idempotency-Key: <uuid><br/>{"type":"DEPOSITO","amount":100.50}

    TS->>LS: GET /api/v1/auth/me<br/>Authorization: Bearer <token>
    Note over TS,LS: Circuit Breaker + Retry (Resilience4j)
    LS-->>TS: 200 OK {userId, channel, contractado}

    TS->>TS: Verifica idempotência (X-Idempotency-Key)
    TS->>SQS: Publica evento na fila transactions.fifo<br/>(MessageGroupId para FIFO)
    SQS-->>TS: MessageId confirmado

    TS-->>C: 202 Accepted {"transactionId":"<uuid>"}
```

---

## 5. Fluxo de Gamificação (Consumo SQS)

```mermaid
sequenceDiagram
    participant SQS as LocalStack SQS :4566
    participant GS as GameService :8082
    participant M as MongoDB :27017

    loop Polling a cada 500ms
        GS->>SQS: ReceiveMessage (max 10, wait 20s)
        SQS-->>GS: Mensagem(ns) de transação

        GS->>GS: Verifica idempotência (ProcessedEvent)
        GS->>M: Salva GameEventDocument (game_events)
        GS->>GS: Calcula progresso e missões
        GS->>M: Atualiza CustomerProgress
        GS->>M: Verifica e completa Missions
        GS->>SQS: DeleteMessage (confirma processamento)
    end
```

---

## 6. Fluxo Completo (End-to-End)

```mermaid
graph LR
    A["1️⃣ Login\nPOST /api/v1/auth/login"] --> B["2️⃣ Contratar\nPOST /api/v1/contract"]
    B --> C["3️⃣ Transação\nPOST /transactions"]
    C --> D["4️⃣ SQS\ntransactions.fifo"]
    D --> E["5️⃣ Gamificação\nGameService consome SQS"]
    E --> F["6️⃣ MongoDB\nProgresso salvo em game_db"]
```
