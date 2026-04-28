#!/bin/bash
# Script de inicialização do LocalStack
# Cria a fila FIFO de transações automaticamente

echo "=== Criando filas SQS ==="

awslocal sqs create-queue \
  --queue-name transactions.fifo \
  --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"false"}' \
  --region us-east-1

echo "=== Fila transactions.fifo criada com sucesso ==="

awslocal sqs list-queues
