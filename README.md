# 🏦 Itaú — Documentação Unificada dos Microsserviços

![Java](https://img.shields.io/badge/Java-21-007396?style=flat&logo=java&logoColor=white)
![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.3.5-6DB33F?style=flat&logo=spring-boot&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat&logo=docker&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7-DC382D?style=flat&logo=redis&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-6.0-47A248?style=flat&logo=mongodb&logoColor=white)
![LocalStack](https://img.shields.io/badge/LocalStack-3.0-4B275F?style=flat&logo=amazon-aws&logoColor=white)

---

## 📦 Serviços

| Serviço | Porta | Descrição |
|---------|-------|-----------|
| **LoginService** | `8081` | Serviço de autenticação JWT com cache Redis |
| **TransactionService** | `8080` | Serviço de transações financeiras com idempotência via SQS |
| **GameService** | `8082` | Serviço de gamificação que consome eventos SQS e persiste no MongoDB |

---

## ✅ Pré-requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado e em execução
- Portas livres: **8080**, **8081**, **8082**, **6379**, **27017**, **4566**

---

## 🚀 Início Rápido

```bash
# Subir todos os serviços
docker-compose up -d
```

---

## 📚 Documentação

| Arquivo | Conteúdo |
|---------|----------|
| [01-ARQUITETURA.md](01-ARQUITETURA.md) | Diagrama da arquitetura e tecnologias utilizadas |
| [02-INSTALACAO.md](02-INSTALACAO.md) | Instalação de dependências e clone dos repositórios |
| [03-EXECUCAO.md](03-EXECUCAO.md) | Comandos para subir, parar e monitorar os serviços |
| [04-ENDPOINTS.md](04-ENDPOINTS.md) | Tabela completa de endpoints |
| [05-FLUXOS.md](05-FLUXOS.md) | Diagramas de fluxo (login, contratação, transação, gamificação) |
| [06-REDIS.md](06-REDIS.md) | Comandos úteis Redis |
| [07-MONGODB.md](07-MONGODB.md) | Collections e comandos MongoDB |
| [08-SQS.md](08-SQS.md) | Comandos LocalStack/SQS |
| [09-TROUBLESHOOTING.md](09-TROUBLESHOOTING.md) | Erros comuns e soluções |
| [10-TESTES.md](10-TESTES.md) | Exemplos curl e collection Postman |
| [docker-compose-full.yml](docker-compose-full.yml) | Docker Compose unificado com todos os serviços |
| [postman-collection.json](postman-collection.json) | Collection Postman pronta para importar |
