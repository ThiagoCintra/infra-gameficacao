# 🏦 — Documentação Unificada dos Microsserviços

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

---

## 🧠 Por que escolhi este modelo de arquitetura?

### 1. Arquitetura Orientada a Eventos (Event-Driven)
**Motivação:** Garantir que a gamificação **nunca impacte a transação financeira principal**.

- Transações retornam **imediato** (202 Accepted)
- Gamificação processa **assíncrona**
- Cliente não espera processamento de regras

**Decisão crítica:** Usei SQS em vez de chamada REST síncrona para desacoplar completamente os serviços.

### 2. Separação em 3 Microsserviços

| Serviço | Responsabilidade | Tecnologia |
|---------|----------------|------------|
| **LoginService** | Autenticação, JWT, sessão | Redis, H2 JPA |
| **TransactionService** | Validar transação, publicar evento | SQS, Resilience4j |
| **GameService** | Processar gamificação, pontuar, nível | MongoDB + H2 |

**Por que não um monolito?** Permite escalar cada serviço independentemente, evoluir regras de gamificação sem tocar no core bancário, e isolar falhas.

### 3. Uso de Mensageria (SQS)
- **Baixo acoplamento:** GameService pode cair que transações continuam
- **Resiliência:** Mensagens persistem, reprocessamento automático
- **Escalabilidade:** Múltiplos consumidores em paralelo

### 4. Persistência Híbrida (JPA + MongoDB)
- **JPA (H2/PostgreSQL):** Dados estruturados (CustomerProgress, ProcessedEvent) que precisam de consistência forte e transações
- **MongoDB:** Dados não estruturados (game_events), flexíveis para evolução de regras

*O próprio desafio pedia "dados não estruturados" – MongoDB atende perfeitamente.*

### 5. Idempotência (ponto crítico)
- SQS tem "at-least-once delivery"
- **ProcessedEvent com `@Indexed(unique=true)`** garante que mesmo com mensagens duplicadas, cada evento é processado **exatamente uma vez**

### 6. Resiliência com Resilience4j
- Circuit Breaker na chamada `/me` (LoginService)
- Retry com backoff exponencial
- Fallback (Fail-fast seguro)

### 7. Java 21 (não 25)
Após tentativas frustradas com Java 25 (imagens Docker não existem, Maven não suporta `--release 25`), optei por **Java 21 LTS** – estável, compatível, e o que grandes bancos usam em produção.

---

## 🤖 Como o Copilot me ajudou

### 1. Aceleração da implementação inicial
Com poucos prompts, o Copilot gerou os esqueletos dos 3 serviços (Login, Transaction, Game) com estrutura de pacotes bem definida: controllers, services, repositories, domain, infrastructure. Isso me poupou horas de setup inicial e me permitiu focar na lógica de negócio.

### 2. Debugging e correção de erros (mais valioso)
Quando tive erros como:
- `release version 25 not supported`
- `no main manifest attribute`
- `DuplicateKeyException: mongodb`
- `rosetta error: failed to open elf`

**O Copilot me ajudou localmente a:**
- Identificar a causa raiz: Java 25 vs 21 (imagem Maven não suportava), falta do plugin `spring-boot-maven-plugin` no pom.xml, chave `mongodb` duplicada no application.yml, conflito de arquitetura ARM vs AMD64 no meu Mac
- Corrigir os Dockerfiles (trocar de Alpine para Jammy, usar wildcard no `COPY` do JAR)
- Ajustar os poms com as dependências corretas

### 3. Refinamento arquitetural
Através dos prompts, o Copilot me sugeriu:
- Configurar **healthchecks** e `depends_on` com `condition: service_healthy` no docker-compose, garantindo ordem correta de inicialização
- Usar Virtual Threads (Java 21) no consumidor SQS para alta concorrência
- Implementar idempotência via `@Indexed(unique=true)` no MongoDB

### 4. Automação do ambiente
Com o Copilot, criei:
- `docker-compose.yml` completo com LocalStack, MongoDB, Redis e os 3 serviços
- Scripts de inicialização automática das filas SQS (`localstack/init/01-create-queues.sh`)
- Healthchecks e `depends_on` entre serviços, evitando race conditions

### 5. Validação e documentação
O Copilot me ajudou a gerar:
- Testes unitários e de integração (incluindo mocks para SQS e WireMock para `/me`)
- Documentação da arquitetura com diagramas de sequência
- Relatórios de validação (PDF) com logs, evidências e resultados dos testes

---

## 🎯 Resultado Final

| Critério | Status |
|----------|--------|
| Arquitetura orientada a eventos | ✅ Implementado |
| Separação em 3 microsserviços | ✅ Rodando |
| Idempotência (SQS) | ✅ `ProcessedEvent` |
| Resiliência (CB + Retry) | ✅ Resilience4j |
| Observabilidade | ✅ Actuator + Metrics |
| Containerização | ✅ Docker Compose |
| Configuração externa | ✅ 12-factor (env vars) |
| Java compatível | ✅ 21 LTS |

---

## 💬 Minha Conclusão Pessoal

O Copilot foi **um parceiro de arquitetura**, não um substituto. Ele me ajudou a:
- **Validar decisões** (ex: "por que não usar Java 25?")
- **Corrigir rapidamente erros** (ex: explicando o significado do erro no Logback e como ajustar)
- **Automatizar tarefas repetitivas** (scripts, docker-compose)

**Mas as decisões críticas foram minhas:**
- Escolher SQS em vez de REST síncrono
- Manter JPA + MongoDB híbrido
- Implementar idempotência no GameService
- Priorizar consistência sobre performance onde necessário

**O Copilot não pensa como arquiteto – mas me ajudou a pensar mais rápido e com menos erros, localmente, no meu ambiente.**
