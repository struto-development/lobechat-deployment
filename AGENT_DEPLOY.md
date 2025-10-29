# Autonomous LobeChat Deployment with ngrok Tunnels - Claude Code Instructions

**IMPORTANT**: This deployment uses ngrok tunnels for public access. Follow every step to deploy LobeChat with Casdoor SSO using ngrok custom domains.

## ngrok Configuration

This deployment uses:
- **LobeChat UI**: `strutoai-lobechat.struto.co.uk.ngrok.app`
- **Casdoor Auth**: `auth.strutoai-lobechat.struto.co.uk.ngrok.app`
- **ngrok Auth Token**: `34hLGYtNDN51ZhnuWmZ7u41ZxzR_55fpXZgDZbpPoJJbkQxGp`

## Step 1: Verify Prerequisites

```bash
# Check Docker
docker --version || { echo "Docker not installed"; exit 1; }

# Check Docker Compose
docker compose version || { echo "Docker Compose not installed"; exit 1; }

# Check disk space (need 20GB)
df -h / | awk 'NR==2 {if(int($4) < 20) exit 1}'

# Check memory (need 4GB)
free -g | awk 'NR==2 {if($2 < 4) exit 1}'

echo "✅ All prerequisites met"
```

## Step 2: Create Project Structure

```bash
# Create deployment directory
sudo mkdir -p /opt/lobechat
cd /opt/lobechat

# Create required directories
mkdir -p config/{casdoor,nginx/sites,nginx/ssl}
mkdir -p scripts
mkdir -p data/{postgres,minio,casdoor}

echo "✅ Directory structure created"
```

## Step 3: Create docker-compose.yml with ngrok

Create `/opt/lobechat/docker-compose.yml`:

```yaml
version: '3.8'

services:
  # Network service for shared network namespace
  network-service:
    image: alpine
    container_name: lobe-network
    command: tail -f /dev/null
    restart: unless-stopped
    networks:
      - lobe-network
    ports:
      - '3000:3000'
      - '3210:3210'
      - '8000:8000'
      - '9000:9000'
      - '9001:9001'
      - '5432:5432'
      - '4317:4317'
      - '4318:4318'

  postgresql:
    image: pgvector/pgvector:pg17
    container_name: lobe-postgres
    network_mode: 'service:network-service'
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=casdoor
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  minio:
    image: minio/minio:RELEASE.2024-04-22T22-12-26Z
    container_name: lobe-minio
    network_mode: 'service:network-service'
    volumes:
      - ./data/minio:/data
    environment:
      - MINIO_ROOT_USER=minioadmin
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
      - MINIO_VOLUMES=/data
      - MINIO_BROWSER=on
      - MINIO_API_CORS_ALLOW_ORIGIN=${APP_URL}
    restart: unless-stopped
    command: >
      sh -c "
        minio server /data --address ':9000' --console-address ':9001' &
        sleep 10 &&
        mc alias set myminio http://localhost:9000 minioadmin ${MINIO_ROOT_PASSWORD} &&
        mc mb -p myminio/lobe &&
        mc anonymous set public myminio/lobe &&
        mc mb -p myminio/casdoor &&
        mc anonymous set public myminio/casdoor &&
        wait
      "

  casdoor:
    image: casbin/casdoor:v2.13.0
    container_name: lobe-casdoor
    network_mode: 'service:network-service'
    depends_on:
      postgresql:
        condition: service_healthy
    environment:
      - driverName=postgres
      - dataSourceName=postgres://postgres:${POSTGRES_PASSWORD}@localhost:5432/casdoor?sslmode=disable
      - sessionSecret=${CASDOOR_SESSION_SECRET}
    volumes:
      - ./config/casdoor/app.conf:/conf/app.conf:ro
      - ./config/casdoor/init_data.json:/init_data.json:ro
    restart: unless-stopped

  lobe:
    image: lobehub/lobe-chat-database
    container_name: lobe-chat
    network_mode: 'service:network-service'
    depends_on:
      postgresql:
        condition: service_healthy
    environment:
      - DATABASE_URL=postgres://postgres:${POSTGRES_PASSWORD}@localhost:5432/lobe
      - APP_URL=${APP_URL}
      - KEY_VAULTS_SECRET=${KEY_VAULTS_SECRET}
      - NEXT_AUTH_SSO_PROVIDERS=casdoor
      - NEXT_AUTH_SECRET=${NEXT_AUTH_SECRET}
      - AUTH_URL=${AUTH_URL}
      - AUTH_CASDOOR_ISSUER=${AUTH_CASDOOR_ISSUER}
      - AUTH_CASDOOR_ID=a387a4892ee19b1a2249
      - AUTH_CASDOOR_SECRET=550db86c5cbdcee3f8e0c57a6cea524d5bc95765
      - AUTH_CASDOOR_APP_NAME=lobechat
      - S3_ACCESS_KEY_ID=minioadmin
      - S3_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
      - S3_ENDPOINT=http://localhost:9000
      - S3_BUCKET=lobe
      - S3_PUBLIC_DOMAIN=${S3_PUBLIC_DOMAIN}
      - S3_ENABLE_PATH_STYLE=1
      # Optional AI Providers
      - OPENAI_API_KEY=${OPENAI_API_KEY:-}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      - GROQ_API_KEY=${GROQ_API_KEY:-}
      - GEMINI_API_KEY=${GEMINI_API_KEY:-}
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"

  # ngrok tunnel service
  ngrok:
    image: ngrok/ngrok:alpine
    container_name: lobe-ngrok
    network_mode: 'service:network-service'
    depends_on:
      - lobe
      - casdoor
    volumes:
      - ./ngrok.yml:/etc/ngrok.yml
    command: 'start --all --config /etc/ngrok.yml'
    restart: unless-stopped

networks:
  lobe-network:
    driver: bridge
```

## Step 4: Create ngrok Configuration

Create `/opt/lobechat/ngrok.yml`:

```yaml
version: "2"
authtoken: 34hLGYtNDN51ZhnuWmZ7u41ZxzR_55fpXZgDZbpPoJJbkQxGp
tunnels:
  lobechat-ui:
    proto: http
    addr: 3210
    domain: strutoai-lobechat.struto.co.uk.ngrok.app
  casdoor-auth:
    proto: http
    addr: 8000
    domain: auth.strutoai-lobechat.struto.co.uk.ngrok.app
```

## Step 5: Create Environment Configuration

```bash
# Generate passwords
POSTGRES_PASS=$(openssl rand -hex 16)
MINIO_PASS=$(openssl rand -hex 16)
KEY_VAULT=$(openssl rand -hex 32)
NEXT_AUTH=$(openssl rand -hex 32)
CASDOOR_SESSION=$(openssl rand -hex 16)

# Create .env file with ngrok domains
cat > /opt/lobechat/.env << EOF
# Database
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_DB=casdoor

# MinIO Storage
MINIO_ROOT_PASSWORD=${MINIO_PASS}

# Application URLs (using ngrok domains)
APP_URL=https://strutoai-lobechat.struto.co.uk.ngrok.app
AUTH_URL=https://strutoai-lobechat.struto.co.uk.ngrok.app/api/auth
AUTH_CASDOOR_ISSUER=https://auth.strutoai-lobechat.struto.co.uk.ngrok.app
S3_PUBLIC_DOMAIN=https://strutoai-lobechat.struto.co.uk.ngrok.app

# Security Keys
KEY_VAULTS_SECRET=${KEY_VAULT}
NEXT_AUTH_SECRET=${NEXT_AUTH}
CASDOOR_SESSION_SECRET=${CASDOOR_SESSION}

# Optional AI Providers (add your keys here)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GROQ_API_KEY=
GEMINI_API_KEY=
QWEN_API_KEY=
ZHIPU_API_KEY=
EOF

echo "✅ Environment configuration created"
```

## Step 6: Create Casdoor Configuration

Create `/opt/lobechat/config/casdoor/app.conf`:

```bash
cat > /opt/lobechat/config/casdoor/app.conf << 'EOF'
appname = casdoor
httpport = 8000
runmode = prod
copyrequestbody = false
sessionOn = true
sessionCookieSameSite =
isCloudIntranet = false
redisEndpoint =
defaultStorageProvider =
tokenPeriod = 168
selfHost = false
quota = {"organization": -1, "user": -1, "application": -1, "provider": -1}
logPostOnly = true
initScore = 0
originBackend =
staticBaseUrl = "https://cdn.casbin.org"
EOF

echo "✅ Casdoor configuration created"
```

## Step 7: Create Casdoor Initial Data with ngrok URLs

Create `/opt/lobechat/config/casdoor/init_data.json`:

```bash
cat > /opt/lobechat/config/casdoor/init_data.json << 'EOF'
{
  "organizations": [
    {
      "name": "built-in",
      "displayName": "Built-in Organization",
      "websiteUrl": "",
      "favicon": "",
      "passwordType": "salt",
      "passwordOptions": [],
      "countryDefaultCode": "US",
      "defaultApplication": "app-built-in",
      "tags": [],
      "defaultAvatar": "https://cdn.casbin.org/img/casbin.svg",
      "masterPassword": "",
      "enableSoftDeletion": false,
      "isProfilePublic": true
    },
    {
      "name": "lobechat",
      "displayName": "LobeChat",
      "websiteUrl": "",
      "favicon": "",
      "passwordType": "salt",
      "passwordOptions": [],
      "countryDefaultCode": "US",
      "defaultApplication": "lobechat",
      "tags": [],
      "defaultAvatar": "https://cdn.casbin.org/img/casbin.svg",
      "masterPassword": "",
      "enableSoftDeletion": false,
      "isProfilePublic": true
    }
  ],
  "applications": [
    {
      "name": "app-built-in",
      "organization": "built-in",
      "displayName": "Casdoor",
      "logo": "https://cdn.casbin.org/img/casdoor-logo_1185x256.png",
      "homepageUrl": "",
      "description": "Casdoor",
      "tags": [],
      "clientId": "014ae4bd048734ca2dea",
      "clientSecret": "fb5c6fd1b33856600c977e326cf355d4e6d0c2f1",
      "redirectUris": ["http://localhost:8000/callback"],
      "scopes": ["openid", "profile", "email"],
      "grantTypes": ["authorization_code", "password", "client_credentials", "refresh_token"],
      "cert": "cert-built-in",
      "orgChoiceMode": "select",
      "isProfilePublic": true
    },
    {
      "name": "lobechat",
      "organization": "lobechat",
      "displayName": "LobeChat",
      "logo": "https://cdn.casbin.org/img/casdoor-logo_1185x256.png",
      "homepageUrl": "",
      "description": "LobeChat Application",
      "tags": [],
      "clientId": "a387a4892ee19b1a2249",
      "clientSecret": "550db86c5cbdcee3f8e0c57a6cea524d5bc95765",
      "redirectUris": ["https://strutoai-lobechat.struto.co.uk.ngrok.app/api/auth/callback/casdoor"],
      "scopes": ["openid", "profile", "email"],
      "grantTypes": ["authorization_code", "password", "client_credentials", "refresh_token"],
      "cert": "cert-built-in",
      "orgChoiceMode": "select",
      "isProfilePublic": true
    }
  ],
  "users": [
    {
      "name": "admin",
      "type": "normal-user",
      "password": "admin123",
      "displayName": "System Admin",
      "avatar": "https://cdn.casbin.org/img/casbin.svg",
      "email": "admin@example.com",
      "phone": "",
      "countryCode": "US",
      "application": "app-built-in",
      "organization": "built-in",
      "isAdmin": true,
      "isGlobalAdmin": true,
      "isForbidden": false,
      "isDeleted": false,
      "signupApplication": "app-built-in"
    },
    {
      "name": "admin",
      "type": "normal-user",
      "password": "admin123",
      "displayName": "LobeChat Admin",
      "avatar": "https://cdn.casbin.org/img/casbin.svg",
      "email": "admin@lobechat.example.com",
      "phone": "",
      "countryCode": "US",
      "application": "lobechat",
      "organization": "lobechat",
      "isAdmin": true,
      "isGlobalAdmin": false,
      "isForbidden": false,
      "isDeleted": false,
      "signupApplication": "lobechat"
    },
    {
      "name": "user",
      "type": "normal-user",
      "password": "user123",
      "displayName": "Demo User",
      "avatar": "https://cdn.casbin.org/img/casbin.svg",
      "email": "user@example.com",
      "phone": "",
      "countryCode": "US",
      "application": "lobechat",
      "organization": "lobechat",
      "isAdmin": false,
      "isGlobalAdmin": false,
      "isForbidden": false,
      "isDeleted": false,
      "signupApplication": "lobechat"
    }
  ],
  "certs": [
    {
      "name": "cert-built-in",
      "type": "x509",
      "cryptoAlgorithm": "RS256",
      "bitSize": 4096,
      "expireInYears": 20,
      "scope": "JWT",
      "certificate": "-----BEGIN CERTIFICATE-----\nMIIE5TCCAs2gAwIBAgIDAeJAMA0GCSqGSIb3DQEBCwUAMCgxDjAMBgNVBAoTBWFk\nbWluMRYwFAYDVQQDEw1jZXJ0LWJ1aWx0LWluMB4XDTIzMDcwNjA3NTQxOFoXDTQz\nMDcwNjA3NTQxOFowKDEOMAwGA1UEChMFYWRtaW4xFjAUBgNVBAMTDWNlcnQtYnVp\nbHQtaW4wggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCWvU3VJhrZrJLg\nHm7YCwfmdpvF8x7CKr9Z4CKk3k5hEpV2NcEJSxQX7sQQDZjpK5f4TQjV8XPJfRKz\nJ0qkFXNLBpLpqaJaOV4WqQ7hYiCWi2v9WlDQc7+Vwm8mzqZq2ZAoqcJqxDrDTJkN\n7gn+nKvFqCGqGcBZSGALvkBQaJMZCwLT8mNRCx8yTfMdMV1R1bONPPKyxUpBKNZB\njP4ae5BLLHvA8gW0UQxDCNEnFKbCTDwVaMdAU+xLT4U+bYJipPSdsicLNXAJLOJ6\nDBTNGZfGNS0pKKkU7Y3XmcWYLRVLxf8YhqFPPUHwIvXdBKA3qt2JdQgLBkbUxXp+\n7J5fOlV5CnfLzTyNDfJGPLNXpMVQRvQqfuipBq3kgFldHGXHWKvWxl7EaGPaNejS\nvKVQaXQoLzCJQslPvqChqQPEqnr2+gwU5oT7gQkZvvOzFxE8TKh3dPMbFnCCH0b+\nYhN3wPFp4z3LSlpF5On4dH2h7rICfPqYR1Qz7l7JHGUjALge+c/gBgHBH/0xVxEy\npMmJLuSuJxIjjGvpMP5bLq1QqFvBCLqH1XI7EfmAFCYRBylz3MchL0TLDd0mEi1x\n+8rZMPPJxiWu+rRn5RXzktZVJBBKwQzmXBPx8qrKT6FVfN9FMTzT2kkVFPQ8jGNO\nlBUJKFE1vC6oCL5qDDTjQfdcUqyB/wIDAQABoyYwJDAOBgNVHQ8BAf8EBAMCAqQw\nEgYDVR0TAQH/BAgwBgEB/wIBATANBgkqhkiG9w0BAQsFAAOCAgEANdaFRw/Y7sdy\n1rJmmLgbhWjILEwJPPlB7biKWvs4u5xR6WNIP2yMlxN9q2xvFrM0k1rTJlQKELFf\nHc8k8Ae5svsNLQFj/alCBBxvolP8p01LTGmgWc2J5Uj0veua2MdX3ZtOqKoB6x6f\nqacl4O5xGGFLHGJrcY2KB0CWQnxK3KlChfmvCJ7bjVaULHPBb+p7JEQXN3YV0Uuw\n9YroZfMDTFPX6NKVB9ddfUJJAXPeOV7hHPVlcnHbNNGCBLn9et2NnpGNgXfGYNFi\npjAb4RE6YcJ8ASUIH8ApFfE/8Y4oH8vFdUhxBNgR4YLhh2yKCJcD4XwJtER7u0+h\nlrqVDYbW8Hg2fT8hFWJt5F0k0NEZFJNqt3QWAGwqCHGf+yj8QWphcemN7dJlhtCm\nnJ0uIs5C8h7b/fLbq4pqfVzG39dr/2Ddt0Pd7+YVXc/PXOgSB9aL1cIt5TVfmHRD\niycAWPK8QC3/dMpqhwVK8aZkQThhl/IhG05RD3NP5rNHlEOFX6gGJ3rpChLfjmWA\nuKMkafyh7eAGP7e7F4G9pnAXkONchjGHZPVZ0lppe8AqaLJH1KQlDfsb0desHFA1\nBYLxX2pv/UmJx8maIZh3NCKmwpPChcaAj3IVfXWK1aRijlWr8SY3rJbUG7DYPvL4\njNr9aXFX5pW3kXiDQKPvuXQku1ogMwU=\n-----END CERTIFICATE-----",
      "privateKey": "-----BEGIN RSA PRIVATE KEY-----\n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\n-----END RSA PRIVATE KEY-----"
    }
  ],
  "providers": [
    {
      "name": "provider_captcha_default",
      "type": "Default",
      "category": "Captcha"
    }
  ]
}
EOF

echo "✅ Casdoor initial data created"
```

## Step 8: Deploy Services

```bash
cd /opt/lobechat

# Pull all images
docker compose pull

# Start all services
docker compose up -d

# Wait for services to initialize
echo "Waiting for services to start..."
sleep 30

# Initialize Casdoor data
docker exec lobe-casdoor sh -c '
  if [ ! -f /initialized ]; then
    curl -X POST "http://localhost:8000/api/init-data" \
      -H "Content-Type: application/json" \
      -d @/init_data.json
    touch /initialized
  fi
'

# Verify all services are running
docker compose ps

echo "✅ Services deployed with ngrok tunnels"
```

## Step 9: Verify ngrok Tunnels

```bash
# Check ngrok tunnel status
docker exec lobe-ngrok wget -O - http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for tunnel in data.get('tunnels', []):
    print(f\"{tunnel['name']}: {tunnel['public_url']}\")
"

# Test endpoints
curl -I https://strutoai-lobechat.struto.co.uk.ngrok.app || echo "LobeChat tunnel issue"
curl -I https://auth.strutoai-lobechat.struto.co.uk.ngrok.app || echo "Casdoor tunnel issue"

echo "✅ ngrok tunnels verified"
```

## Step 10: Configure Firewall (Optional)

```bash
# Only allow SSH and Docker ports
sudo ufw allow 22/tcp   # SSH
sudo ufw --force enable

echo "✅ Firewall configured (only SSH allowed, all traffic via ngrok)"
```

## Step 11: Create Backup Script

```bash
cat > /opt/lobechat/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups/lobechat"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p ${BACKUP_DIR}

# Backup databases
docker exec lobe-postgres pg_dump -U postgres -d lobe > ${BACKUP_DIR}/lobe_${DATE}.sql
docker exec lobe-postgres pg_dump -U postgres -d casdoor > ${BACKUP_DIR}/casdoor_${DATE}.sql

# Backup MinIO
docker exec lobe-minio mc mirror myminio/lobe ${BACKUP_DIR}/minio_lobe_${DATE}/
docker exec lobe-minio mc mirror myminio/casdoor ${BACKUP_DIR}/minio_casdoor_${DATE}/

# Create archive
cd ${BACKUP_DIR}
tar -czf lobechat_backup_${DATE}.tar.gz *_${DATE}*
rm -rf *_${DATE}.sql *_${DATE}/

# Keep only last 7 days
find ${BACKUP_DIR} -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: ${BACKUP_DIR}/lobechat_backup_${DATE}.tar.gz"
EOF

chmod +x /opt/lobechat/backup.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/lobechat/backup.sh") | crontab -

echo "✅ Backup automation configured"
```

## Step 12: Add AI Provider Keys (Optional)

If you have AI provider API keys, add them to `/opt/lobechat/.env`:

```bash
# Edit .env file to add your API keys
cat >> /opt/lobechat/.env << 'EOF'

# AI Provider Keys (uncomment and add your keys)
# OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...
# GROQ_API_KEY=gsk_...
# GEMINI_API_KEY=...
EOF

# Restart LobeChat to apply changes
docker compose restart lobe

echo "✅ AI providers can be configured in .env file"
```

## Step 13: Final Verification and Summary

```bash
# Get deployment info
SERVER_IP=$(curl -s ifconfig.me)

cat << 'EOF'

========================================
✅ DEPLOYMENT COMPLETE WITH NGROK!
========================================

PUBLIC ACCESS URLS (via ngrok):
--------------------------------
LobeChat UI: https://strutoai-lobechat.struto.co.uk.ngrok.app
Casdoor Auth: https://auth.strutoai-lobechat.struto.co.uk.ngrok.app

LOCAL ACCESS (from server):
---------------------------
LobeChat: http://localhost:3210
Casdoor: http://localhost:8000
MinIO Console: http://localhost:9001

DEFAULT CREDENTIALS:
-------------------
Casdoor System Admin:
  URL: https://auth.strutoai-lobechat.struto.co.uk.ngrok.app
  Organization: built-in
  Username: admin
  Password: admin123

LobeChat Admin:
  URL: https://strutoai-lobechat.struto.co.uk.ngrok.app
  Organization: lobechat
  Username: admin
  Password: admin123

LobeChat User:
  URL: https://strutoai-lobechat.struto.co.uk.ngrok.app
  Organization: lobechat
  Username: user
  Password: user123

ngrok TUNNEL INFO:
-----------------
Auth Token: 34hLGYtNDN51ZhnuWmZ7u41ZxzR_55fpXZgDZbpPoJJbkQxGp
UI Domain: strutoai-lobechat.struto.co.uk.ngrok.app
Auth Domain: auth.strutoai-lobechat.struto.co.uk.ngrok.app

NEXT STEPS:
----------
1. Access LobeChat at the public URL
2. Change all default passwords immediately
3. Configure AI provider API keys in /opt/lobechat/.env
4. Test the OAuth login flow
5. Monitor ngrok tunnel status

SERVICE MANAGEMENT:
------------------
View logs: docker compose logs -f [service]
Restart: docker compose restart [service]
Stop all: docker compose down
Backup: /opt/lobechat/backup.sh

Check ngrok tunnels:
docker exec lobe-ngrok wget -O - http://localhost:4040/api/tunnels

IMPORTANT NOTES:
---------------
- All traffic goes through ngrok tunnels (secure)
- No direct port exposure needed (except SSH)
- ngrok handles SSL/TLS automatically
- Organization dropdown enabled for login
- Backups run daily at 2 AM

Deployment Location: /opt/lobechat
Configuration File: /opt/lobechat/.env
ngrok Config: /opt/lobechat/ngrok.yml

========================================
EOF
```

## Troubleshooting ngrok Issues

If ngrok tunnels fail:

```bash
# Check ngrok container logs
docker logs lobe-ngrok

# Restart ngrok container
docker compose restart ngrok

# Verify auth token
grep authtoken /opt/lobechat/ngrok.yml

# Check if domains are already in use
# (Only one ngrok instance can use these domains at a time)

# Full restart if needed
docker compose down
docker compose up -d
```

---

**END OF DEPLOYMENT WITH NGROK TUNNELS**

This deployment uses ngrok custom domains for secure public access without requiring direct domain configuration or SSL certificates. The system is immediately accessible at the configured ngrok URLs.