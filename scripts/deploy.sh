#!/bin/bash

# LobeChat Deployment Script
# This script deploys LobeChat with Casdoor authentication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}LobeChat Deployment Script${NC}"
echo "================================"

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
   print_warning "Running as root is not recommended. Consider using a regular user with sudo privileges."
fi

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    print_info "✓ Docker found: $(docker --version)"

    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    print_info "✓ Docker Compose found"

    # Check if .env file exists
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            print_warning ".env file not found. Copying from .env.example..."
            cp .env.example .env
            print_error "Please edit .env file with your configuration before running this script again."
            exit 1
        else
            print_error ".env file not found and no .env.example available."
            exit 1
        fi
    fi
    print_info "✓ .env file found"
}

# Generate secure passwords
generate_passwords() {
    print_info "Generating secure passwords..."

    if grep -q "CHANGE_THIS" .env; then
        print_warning "Found default passwords in .env file. Generating secure ones..."

        # Generate passwords
        POSTGRES_PASS=$(openssl rand -hex 16)
        MINIO_PASS=$(openssl rand -hex 16)
        KEY_VAULT=$(openssl rand -hex 32)
        NEXT_AUTH=$(openssl rand -hex 32)
        CASDOOR_SESSION=$(openssl rand -hex 16)
        SEARXNG=$(openssl rand -hex 16)

        # Update .env file
        sed -i.bak "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASS}/" .env
        sed -i.bak "s/MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=${MINIO_PASS}/" .env
        sed -i.bak "s/KEY_VAULTS_SECRET=.*/KEY_VAULTS_SECRET=${KEY_VAULT}/" .env
        sed -i.bak "s/NEXT_AUTH_SECRET=.*/NEXT_AUTH_SECRET=${NEXT_AUTH}/" .env
        sed -i.bak "s/CASDOOR_SESSION_SECRET=.*/CASDOOR_SESSION_SECRET=${CASDOOR_SESSION}/" .env
        sed -i.bak "s/SEARXNG_SECRET=.*/SEARXNG_SECRET=${SEARXNG}/" .env

        print_info "✓ Secure passwords generated and saved"
    else
        print_info "✓ Passwords already configured"
    fi
}

# Update domain configuration
update_domains() {
    print_info "Configuring domains..."

    read -p "Enter your domain name (e.g., example.com): " DOMAIN

    if [ -z "$DOMAIN" ]; then
        print_error "Domain name cannot be empty"
        exit 1
    fi

    # Update .env file
    sed -i.bak "s|APP_URL=.*|APP_URL=https://chat.${DOMAIN}|" .env
    sed -i.bak "s|AUTH_URL=.*|AUTH_URL=https://chat.${DOMAIN}/api/auth|" .env
    sed -i.bak "s|AUTH_CASDOOR_ISSUER=.*|AUTH_CASDOOR_ISSUER=https://auth.${DOMAIN}|" .env
    sed -i.bak "s|S3_PUBLIC_DOMAIN=.*|S3_PUBLIC_DOMAIN=https://s3.${DOMAIN}|" .env
    sed -i.bak "s|DOMAIN_NAME=.*|DOMAIN_NAME=${DOMAIN}|" .env

    # Update nginx config
    sed -i.bak "s/your-domain.com/${DOMAIN}/g" config/nginx/sites/lobechat.conf

    # Update Casdoor redirect URI
    jq --arg url "https://chat.${DOMAIN}/api/auth/callback/casdoor" \
       '.applications[1].redirectUris = [$url]' \
       config/casdoor/init_data.json > config/casdoor/init_data.json.tmp && \
       mv config/casdoor/init_data.json.tmp config/casdoor/init_data.json

    print_info "✓ Domain configured: ${DOMAIN}"
}

# Create necessary directories
setup_directories() {
    print_info "Creating necessary directories..."

    mkdir -p config/nginx/ssl
    mkdir -p data/{postgres,minio,casdoor}

    print_info "✓ Directories created"
}

# Deploy services
deploy_services() {
    print_info "Deploying services..."

    # Stop existing services if any
    docker compose down 2>/dev/null || true

    # Deploy based on environment
    read -p "Deploy with nginx reverse proxy? (recommended for production) [y/N]: " USE_NGINX

    if [[ "$USE_NGINX" =~ ^[Yy]$ ]]; then
        print_info "Deploying with nginx..."
        docker compose --profile production up -d
    else
        print_info "Deploying without nginx..."
        docker compose up -d
    fi

    print_info "Waiting for services to start..."
    sleep 10

    # Check service status
    docker compose ps

    print_info "✓ Services deployed successfully"
}

# Initialize Casdoor
initialize_casdoor() {
    print_info "Initializing Casdoor..."

    # Wait for Casdoor to be ready
    for i in {1..30}; do
        if curl -s http://localhost:8000 > /dev/null; then
            print_info "✓ Casdoor is ready"
            break
        fi
        print_info "Waiting for Casdoor to start... ($i/30)"
        sleep 2
    done

    print_info "✓ Casdoor initialized"
}

# Print access information
print_access_info() {
    source .env

    echo ""
    echo "================================"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo "================================"
    echo ""
    echo "Access URLs:"
    echo "-----------"
    echo "LobeChat: ${APP_URL}"
    echo "Casdoor: ${AUTH_CASDOOR_ISSUER}"
    echo "MinIO Console: http://localhost:9001"
    echo ""
    echo "Default Credentials:"
    echo "-------------------"
    echo "Casdoor System Admin:"
    echo "  Organization: built-in"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo "LobeChat Admin:"
    echo "  Organization: lobechat"
    echo "  Username: admin"
    echo "  Password: CHANGE_THIS_PASSWORD (update in Casdoor)"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC}"
    echo "1. Change all default passwords immediately"
    echo "2. Configure SSL certificates in config/nginx/ssl/"
    echo "3. Review and adjust security settings in .env"
    echo "4. Set up backups for PostgreSQL and MinIO data"
    echo ""
}

# Main execution
main() {
    echo ""
    check_prerequisites
    generate_passwords
    update_domains
    setup_directories
    deploy_services
    initialize_casdoor
    print_access_info
}

# Run main function
main "$@"