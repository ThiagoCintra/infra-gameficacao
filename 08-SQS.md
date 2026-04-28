# 📨 SQS (LocalStack)

O **LocalStack** simula os serviços AWS localmente. Neste projeto, apenas o serviço **SQS** é utilizado para comunicação assíncrona entre o TransactionService (produtor) e o GameService (consumidor).

## Configuração

| Parâmetro | Valor |
|-----------|-------|
| Endpoint | `http://localhost:4566` |
| Região | `us-east-1` |
| Imagem Docker | `localstack/localstack:3.0` |
| Serviços habilitados | `sqs` |
| Fila principal | `transactions.fifo` |

---

## Pré-requisito: awslocal

O `awslocal` é um wrapper do AWS CLI configurado para apontar para o LocalStack.

```bash
# Instalar awslocal
pip install awscli-local

# Ou usar diretamente o AWS CLI com endpoint configurado
aws --endpoint-url=http://localhost:4566 sqs list-queues
```

---

## Criar a Fila FIFO

```bash
# Criar fila FIFO de transações (executar após subir o LocalStack)
awslocal sqs create-queue \
  --queue-name transactions.fifo \
  --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"false"}' \
  --region us-east-1
```

> 💡 O arquivo `localstack/init/` contém scripts que criam a fila automaticamente ao iniciar o LocalStack via Docker Compose.

---

## Listar Filas

```bash
awslocal sqs list-queues
```

Saída esperada:
```json
{
    "QueueUrls": [
        "http://localstack:4566/000000000000/transactions.fifo"
    ]
}
```

---

## Enviar Mensagem (Teste Manual)

```bash
awslocal sqs send-message \
  --queue-url http://localhost:4566/000000000000/transactions.fifo \
  --message-body '{"eventId":"test-001","customerId":"user-123","type":"DEPOSITO","amount":50.00}' \
  --message-group-id "user-123" \
  --message-deduplication-id "test-001" \
  --region us-east-1
```

---

## Receber Mensagem (Inspeção Manual)

```bash
awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/transactions.fifo \
  --max-number-of-messages 10 \
  --region us-east-1
```

---

## Obter Atributos da Fila

```bash
awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/transactions.fifo \
  --attribute-names All \
  --region us-east-1
```

Atributos importantes:
- `ApproximateNumberOfMessages` — mensagens disponíveis para leitura
- `ApproximateNumberOfMessagesNotVisible` — mensagens em processamento

---

## Purgar a Fila (limpar mensagens)

```bash
awslocal sqs purge-queue \
  --queue-url http://localhost:4566/000000000000/transactions.fifo \
  --region us-east-1
```

---

## Deletar a Fila

```bash
awslocal sqs delete-queue \
  --queue-url http://localhost:4566/000000000000/transactions.fifo \
  --region us-east-1
```

---

## Verificar Saúde do LocalStack

```bash
curl -s http://localhost:4566/_localstack/health | python3 -m json.tool
```

Saída esperada:
```json
{
  "services": {
    "sqs": "running"
  },
  "version": "3.x.x"
}
```

---

## Configuração Automática via Init Scripts

O Docker Compose monta o diretório `./localstack/init` em `/etc/localstack/init/ready.d`. Os scripts `.sh` nesse diretório são executados automaticamente quando o LocalStack está pronto, criando as filas necessárias.

```bash
# Estrutura esperada
localstack/
└── init/
    └── 01_create_queues.sh  ← cria transactions.fifo automaticamente
```
