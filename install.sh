#!/bin/bash

#############################################################################
# LobeChat Production Deployment Script with ngrok Tunnels
#
# Usage: curl -sL https://raw.githubusercontent.com/struto-development/lobechat-deployment/main/install.sh | sudo bash
#
# This script deploys LobeChat with Casdoor SSO using ngrok custom domains
# for secure public access without requiring direct domain configuration.
#############################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/lobechat"
NGROK_AUTH_TOKEN="34hLGYtNDN51ZhnuWmZ7u41ZxzR_55fpXZgDZbpPoJJbkQxGp"
LOBECHAT_DOMAIN="strutoai-lobechat.struto.co.uk.ngrok.app"
CASDOOR_DOMAIN="auth.strutoai-lobechat.struto.co.uk.ngrok.app"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check logs above for details."
    exit 1
}

# Cleanup on failure
cleanup_on_failure() {
    log_warning "Cleaning up failed deployment..."
    cd "${INSTALL_DIR}" 2>/dev/null && docker compose down -v 2>/dev/null || true
    log_info "Cleanup complete. You can retry the installation."
}

trap cleanup_on_failure ERR

# Banner
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   LobeChat Production Deployment with ngrok Tunnels       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info "Starting LobeChat deployment to ${INSTALL_DIR}"
log_info "Using ngrok domains:"
log_info "  - LobeChat UI: https://${LOBECHAT_DOMAIN}"
log_info "  - Casdoor Auth: https://${CASDOOR_DOMAIN}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root. Please use: sudo bash install.sh"
fi

#############################################################################
# Port Range Configuration
#############################################################################

echo ""
log_info "=== Port Range Configuration ==="
echo ""
echo "This deployment requires 8 ports for the following services:"
echo "  1. LobeChat UI"
echo "  2. Casdoor Authentication"
echo "  3. MinIO API"
echo "  4. MinIO Console"
echo "  5. PostgreSQL Database"
echo "  6-8. Additional services (metrics, observability)"
echo ""

# Function to check if port is available
check_port_available() {
    local port=$1
    if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        return 1  # Port in use
    fi
    return 0  # Port available
}

# Prompt for port range
while true; do
    read -p "Enter starting port number (e.g., 8000): " PORT_START
    read -p "Enter ending port number (e.g., 8010): " PORT_END

    # Validate inputs are numbers
    if ! [[ "$PORT_START" =~ ^[0-9]+$ ]] || ! [[ "$PORT_END" =~ ^[0-9]+$ ]]; then
        log_error "Port numbers must be integers"
        continue
    fi

    # Validate range
    if [ "$PORT_START" -lt 1024 ] || [ "$PORT_START" -gt 65535 ]; then
        log_error "Starting port must be between 1024 and 65535"
        continue
    fi

    if [ "$PORT_END" -lt "$PORT_START" ]; then
        log_error "Ending port must be greater than starting port"
        continue
    fi

    # Check if range has enough ports
    PORT_COUNT=$((PORT_END - PORT_START + 1))
    if [ "$PORT_COUNT" -lt 8 ]; then
        log_error "Port range too small. Need at least 8 ports, you provided ${PORT_COUNT}"
        continue
    fi

    # Check if ports in range are available
    log_info "Checking port availability in range ${PORT_START}-${PORT_END}..."
    PORTS_IN_USE=0
    for ((port=PORT_START; port<=PORT_END; port++)); do
        if ! check_port_available "$port"; then
            log_warning "Port ${port} is already in use"
            ((PORTS_IN_USE++))
        fi
    done

    if [ "$PORTS_IN_USE" -gt 0 ]; then
        log_warning "Found ${PORTS_IN_USE} port(s) already in use in this range"
        read -p "Continue anyway? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            continue
        fi
    fi

    break
done

# Assign ports from the range
PORT_LOBECHAT=$PORT_START
PORT_CASDOOR=$((PORT_START + 1))
PORT_MINIO_API=$((PORT_START + 2))
PORT_MINIO_CONSOLE=$((PORT_START + 3))
PORT_POSTGRES=$((PORT_START + 4))
PORT_EXTRA_1=$((PORT_START + 5))
PORT_EXTRA_2=$((PORT_START + 6))
PORT_EXTRA_3=$((PORT_START + 7))

log_success "Port assignments:"
echo "  LobeChat UI:      ${PORT_LOBECHAT}"
echo "  Casdoor Auth:     ${PORT_CASDOOR}"
echo "  MinIO API:        ${PORT_MINIO_API}"
echo "  MinIO Console:    ${PORT_MINIO_CONSOLE}"
echo "  PostgreSQL:       ${PORT_POSTGRES}"
echo "  Network Service:  ${PORT_EXTRA_1}"
echo "  Metrics (OTLP):   ${PORT_EXTRA_2}"
echo "  Metrics (HTTP):   ${PORT_EXTRA_3}"
echo ""
read -p "Press Enter to continue with deployment..."
echo ""

#############################################################################
# Step 1: Prerequisites Check
#############################################################################

log_info "Step 1/13: Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    error_exit "Docker is not installed. Please install Docker first."
fi
log_success "Docker found: $(docker --version | head -1)"

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    error_exit "Docker Compose is not installed. Please install Docker Compose first."
fi
log_success "Docker Compose found: $(docker compose version | head -1)"

# Check disk space (need at least 20GB free)
AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "${AVAILABLE_SPACE}" -lt 20 ]; then
    error_exit "Insufficient disk space. Need at least 20GB, have ${AVAILABLE_SPACE}GB"
fi
log_success "Disk space available: ${AVAILABLE_SPACE}GB"

# Check memory (need at least 4GB)
AVAILABLE_MEM=$(free -g | awk 'NR==2 {print $2}')
if [ "${AVAILABLE_MEM}" -lt 4 ]; then
    log_warning "Low memory detected: ${AVAILABLE_MEM}GB (recommended: 4GB+)"
else
    log_success "Memory available: ${AVAILABLE_MEM}GB"
fi

# Check required commands
for cmd in curl openssl; do
    if ! command -v ${cmd} &> /dev/null; then
        error_exit "${cmd} is not installed"
    fi
done
log_success "All prerequisites met"

#############################################################################
# Step 2: Create Project Structure
#############################################################################

log_info "Step 2/13: Creating project structure..."

# Create main directory
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Create subdirectories
mkdir -p config/{casdoor,nginx/sites,nginx/ssl}
mkdir -p scripts
mkdir -p data/{postgres,minio,casdoor}

log_success "Directory structure created at ${INSTALL_DIR}"

#############################################################################
# Step 3: Generate Passwords and Environment
#############################################################################

log_info "Step 3/13: Generating secure passwords and environment configuration..."

POSTGRES_PASS=$(openssl rand -hex 16)
MINIO_PASS=$(openssl rand -hex 16)
KEY_VAULT=$(openssl rand -hex 32)
NEXT_AUTH=$(openssl rand -hex 32)
CASDOOR_SESSION=$(openssl rand -hex 16)

cat > "${INSTALL_DIR}/.env" << EOF
# Database
POSTGRES_PASSWORD=${POSTGRES_PASS}
POSTGRES_DB=casdoor

# MinIO Storage
MINIO_ROOT_PASSWORD=${MINIO_PASS}

# Application URLs (using ngrok domains)
APP_URL=https://${LOBECHAT_DOMAIN}
AUTH_URL=https://${LOBECHAT_DOMAIN}/api/auth
AUTH_CASDOOR_ISSUER=https://${CASDOOR_DOMAIN}
S3_PUBLIC_DOMAIN=https://${LOBECHAT_DOMAIN}

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

chmod 600 "${INSTALL_DIR}/.env"
log_success "Environment configuration created with secure passwords"

#############################################################################
# Step 4: Create Docker Compose Configuration
#############################################################################

log_info "Step 4/13: Creating Docker Compose configuration..."

cat > "${INSTALL_DIR}/docker-compose.yml" << COMPOSE_EOF
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
      - '${PORT_EXTRA_1}:3000'
      - '${PORT_LOBECHAT}:3210'
      - '${PORT_CASDOOR}:8000'
      - '${PORT_MINIO_API}:9000'
      - '${PORT_MINIO_CONSOLE}:9001'
      - '${PORT_POSTGRES}:5432'
      - '${PORT_EXTRA_2}:4317'
      - '${PORT_EXTRA_3}:4318'

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
    image: minio/minio:latest
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
      minio:
        condition: service_started
      casdoor:
        condition: service_started
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
COMPOSE_EOF

log_success "Docker Compose configuration created"

#############################################################################
# Step 5: Create ngrok Configuration
#############################################################################

log_info "Step 5/13: Creating ngrok tunnel configuration..."

cat > "${INSTALL_DIR}/ngrok.yml" << EOF
version: "2"
authtoken: ${NGROK_AUTH_TOKEN}
tunnels:
  lobechat-ui:
    proto: http
    addr: 3210
    domain: ${LOBECHAT_DOMAIN}
  casdoor-auth:
    proto: http
    addr: 8000
    domain: ${CASDOOR_DOMAIN}
EOF

log_success "ngrok configuration created"

#############################################################################
# Step 6: Create Casdoor Configuration
#############################################################################

log_info "Step 6/13: Creating Casdoor configuration..."

cat > "${INSTALL_DIR}/config/casdoor/app.conf" << 'EOF'
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

log_success "Casdoor configuration created"

#############################################################################
# Step 7: Create Casdoor Initial Data
#############################################################################

log_info "Step 7/13: Creating Casdoor initial data with ngrok URLs..."

cat > "${INSTALL_DIR}/config/casdoor/init_data.json" << CASDOOR_EOF
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
      "redirectUris": ["https://${LOBECHAT_DOMAIN}/api/auth/callback/casdoor"],
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
CASDOOR_EOF

log_success "Casdoor initial data created with ngrok URLs"

#############################################################################
# Step 8: Pull Docker Images
#############################################################################

log_info "Step 8/13: Pulling Docker images (this may take several minutes)..."

docker compose pull 2>&1 | while IFS= read -r line; do
    echo "  $line"
done

log_success "All Docker images pulled successfully"

#############################################################################
# Step 9: Start PostgreSQL and Create Databases
#############################################################################

log_info "Step 9/13: Starting PostgreSQL and creating databases..."

# Start PostgreSQL first
docker compose up -d postgresql

# Wait for PostgreSQL to be ready with progress indicator
log_info "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec lobe-postgres pg_isready -U postgres &>/dev/null; then
        log_success "PostgreSQL is ready"
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 30 ]; then
        error_exit "PostgreSQL failed to start after 60 seconds"
    fi
done

# Create the lobe database (critical step to prevent migration errors)
log_info "Creating 'lobe' database..."
if docker exec lobe-postgres psql -U postgres -c "CREATE DATABASE lobe;" 2>/dev/null; then
    log_success "Database 'lobe' created successfully"
else
    log_warning "Database 'lobe' may already exist, continuing..."
fi

#############################################################################
# Step 10: Start All Services
#############################################################################

log_info "Step 10/13: Starting all services..."

docker compose up -d

# Wait for services to initialize
log_info "Waiting for services to initialize (20 seconds)..."
for i in {1..20}; do
    echo -n "."
    sleep 1
done
echo ""

log_success "All services started"

#############################################################################
# Step 11: Initialize Casdoor
#############################################################################

log_info "Step 11/13: Initializing Casdoor SSO..."

# Give Casdoor a moment to fully start
sleep 5

# Initialize Casdoor data
if docker exec lobe-casdoor sh -c '
  if [ ! -f /initialized ]; then
    sleep 5
    curl -X POST "http://localhost:8000/api/init-data" \
      -H "Content-Type: application/json" \
      -d @/init_data.json && \
    touch /initialized
  fi
' 2>/dev/null; then
    log_success "Casdoor initialized successfully"
else
    log_warning "Casdoor initialization may have already completed"
fi

#############################################################################
# Step 12: Create Backup Script
#############################################################################

log_info "Step 12/13: Creating backup automation..."

cat > "${INSTALL_DIR}/backup.sh" << 'BACKUP_EOF'
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
BACKUP_EOF

chmod +x "${INSTALL_DIR}/backup.sh"

# Add to crontab (only if not already present)
(crontab -l 2>/dev/null | grep -v "lobechat/backup.sh"; echo "0 2 * * * ${INSTALL_DIR}/backup.sh") | crontab -

log_success "Backup automation configured (daily at 2 AM)"

#############################################################################
# Step 13: Verify Deployment
#############################################################################

log_info "Step 13/13: Verifying deployment..."

# Check container status
log_info "Checking container status..."
docker compose ps

# Wait a bit more for services to stabilize
sleep 10

# Check for critical errors
log_info "Checking for errors in logs..."
if docker logs lobe-chat 2>&1 | tail -20 | grep -iE "error.*database.*not exist" > /dev/null; then
    log_error "Database initialization error detected"
    log_info "Attempting to fix..."
    docker exec lobe-postgres psql -U postgres -c "CREATE DATABASE lobe;" 2>/dev/null || true
    docker compose restart lobe
    sleep 10
fi

# Check ngrok tunnels
log_info "Verifying ngrok tunnels..."
if docker exec lobe-ngrok wget -O - http://localhost:4040/api/tunnels 2>/dev/null | grep -q "public_url"; then
    log_success "ngrok tunnels are active"
else
    log_warning "ngrok tunnel verification inconclusive, check manually"
fi

log_success "Deployment verification complete"

#############################################################################
# Deployment Summary
#############################################################################

# Get server IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to detect")

echo ""
echo -e "${GREEN}"
cat << "SUMMARY_EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║           ✅ DEPLOYMENT COMPLETE WITH NGROK!              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
SUMMARY_EOF
echo -e "${NC}"

cat << SUMMARY_END

${GREEN}PUBLIC ACCESS URLS (via ngrok):${NC}
--------------------------------
LobeChat UI:   https://${LOBECHAT_DOMAIN}
Casdoor Auth:  https://${CASDOOR_DOMAIN}

${BLUE}LOCAL ACCESS (from server):${NC}
---------------------------
LobeChat:      http://localhost:${PORT_LOBECHAT}
Casdoor:       http://localhost:${PORT_CASDOOR}
MinIO API:     http://localhost:${PORT_MINIO_API}
MinIO Console: http://localhost:${PORT_MINIO_CONSOLE}
PostgreSQL:    localhost:${PORT_POSTGRES}

${BLUE}ASSIGNED PORT RANGE:${NC}
---------------------------
Ports ${PORT_START}-${PORT_END} (requested range)
  - LobeChat UI:      ${PORT_LOBECHAT}
  - Casdoor Auth:     ${PORT_CASDOOR}
  - MinIO API:        ${PORT_MINIO_API}
  - MinIO Console:    ${PORT_MINIO_CONSOLE}
  - PostgreSQL:       ${PORT_POSTGRES}
  - Network Service:  ${PORT_EXTRA_1}
  - Metrics (OTLP):   ${PORT_EXTRA_2}
  - Metrics (HTTP):   ${PORT_EXTRA_3}

${YELLOW}DEFAULT CREDENTIALS (CHANGE IMMEDIATELY):${NC}
-------------------
Casdoor System Admin:
  URL: https://${CASDOOR_DOMAIN}
  Organization: built-in
  Username: admin
  Password: admin123

LobeChat Admin:
  URL: https://${LOBECHAT_DOMAIN}
  Organization: lobechat
  Username: admin
  Password: admin123

LobeChat User:
  URL: https://${LOBECHAT_DOMAIN}
  Organization: lobechat
  Username: user
  Password: user123

${BLUE}IMPORTANT NEXT STEPS:${NC}
----------
1. ${RED}Change all default passwords immediately${NC}
2. Configure AI provider API keys in ${INSTALL_DIR}/.env
3. Test the OAuth login flow with all accounts
4. Monitor ngrok tunnel status regularly
5. Review backup configuration

${GREEN}SERVICE MANAGEMENT:${NC}
------------------
View logs:     docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f [service]
Restart:       docker compose -f ${INSTALL_DIR}/docker-compose.yml restart [service]
Stop all:      docker compose -f ${INSTALL_DIR}/docker-compose.yml down
Start all:     docker compose -f ${INSTALL_DIR}/docker-compose.yml up -d
Backup:        ${INSTALL_DIR}/backup.sh

Check tunnels: docker exec lobe-ngrok wget -O - http://localhost:4040/api/tunnels 2>/dev/null | python3 -m json.tool

${YELLOW}IMPORTANT NOTES:${NC}
---------------
- All external traffic goes through ngrok tunnels (secure)
- No direct port exposure needed (firewall can block all except SSH)
- ngrok handles SSL/TLS automatically
- Organization dropdown enabled for login
- Backups run automatically daily at 2 AM
- Deployment location: ${INSTALL_DIR}

${BLUE}FILES:${NC}
------
Configuration:  ${INSTALL_DIR}/.env
Compose File:   ${INSTALL_DIR}/docker-compose.yml
ngrok Config:   ${INSTALL_DIR}/ngrok.yml
Backup Script:  ${INSTALL_DIR}/backup.sh

Server IP: ${SERVER_IP}

╔═══════════════════════════════════════════════════════════╗
║  Your LobeChat instance is now running!                  ║
║  Access it at: https://${LOBECHAT_DOMAIN}
╚═══════════════════════════════════════════════════════════╝

SUMMARY_END

log_success "Installation script completed successfully!"
