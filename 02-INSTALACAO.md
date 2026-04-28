# 🛠️ Instalação

## 1. Instalar o Docker Desktop

### macOS / Windows
Acesse [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/) e baixe o instalador para o seu sistema operacional.

### Linux (Ubuntu/Debian)
```bash
# Atualizar pacotes
sudo apt-get update

# Instalar dependências
sudo apt-get install -y ca-certificates curl gnupg

# Adicionar chave GPG oficial do Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Adicionar repositório
echo \
  "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Adicionar usuário ao grupo docker (evitar uso de sudo)
sudo usermod -aG docker $USER
newgrp docker
```

### Verificar instalação
```bash
docker --version
docker compose version
```

---

## 2. Clonar os Repositórios

```bash
# Criar um diretório de trabalho
mkdir itau-services && cd itau-services

# Clonar repositório de infraestrutura (contém docker-compose)
git clone https://github.com/ThiagoCintra/infra-gameficacao.git

# Clonar os três serviços
git clone https://github.com/ThiagoCintra/LoginService.git
git clone https://github.com/ThiagoCintra/TransactionService.git
git clone https://github.com/ThiagoCintra/GameService.git
```

A estrutura de pastas esperada é:

```
itau-services/
├── infra-gameficacao/   ← docker-compose-full.yml está aqui
├── LoginService/
├── TransactionService/
└── GameService/
```

> ⚠️ O `docker-compose-full.yml` monta cada serviço com `build: ./LoginService`, `build: ./TransactionService` e `build: ./GameService`, portanto os diretórios devem estar no mesmo nível que o arquivo compose.

---

## 3. Verificar Portas Disponíveis

Antes de subir os serviços, certifique-se de que as seguintes portas estão livres:

| Porta | Serviço |
|-------|---------|
| `8081` | LoginService |
| `8080` | TransactionService |
| `8082` | GameService |
| `6379` | Redis |
| `27017` | MongoDB |
| `4566` | LocalStack (SQS) |

```bash
# Verificar portas em uso (Linux/macOS)
lsof -i :8080 -i :8081 -i :8082 -i :6379 -i :27017 -i :4566

# Windows (PowerShell)
netstat -ano | findstr "8080 8081 8082 6379 27017 4566"
```

---

## 4. Variáveis de Ambiente (Opcional)

Os serviços já possuem valores padrão configurados no `docker-compose-full.yml`. Para personalizar, crie um arquivo `.env` na mesma pasta do compose:

```bash
# .env
JWT_SECRET=<sua-chave-secreta-base64-com-pelo-menos-32-caracteres>
JWT_EXPIRATION=86400000
REDIS_HOST=redis
REDIS_PORT=6379
AWS_ENDPOINT=http://localstack:4566
AWS_REGION=us-east-1
SQS_QUEUE_URL=http://localstack:4566/000000000000/transactions.fifo
LOGIN_SERVICE_URL=http://login-service:8081
```

> 🔑 **Importante:** O `JWT_SECRET` deve ser **idêntico** em todos os três serviços para que a validação de tokens funcione corretamente. Para gerar uma chave segura use: `openssl rand -base64 32`
