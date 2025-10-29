# Claude Code Deployment Instructions

This document provides instructions for Claude Code to automatically deploy LobeChat to a production or staging server.

## Prerequisites Check

Claude, please verify these prerequisites on the target server:

```bash
# Check Docker installation
docker --version  # Should be 20.10+
docker compose version  # Should be 2.0+

# Check available resources
df -h  # Need at least 20GB free space
free -h  # Need at least 4GB RAM

# Check network connectivity
ping -c 1 google.com
```

## Step 1: Clone Repository

```bash
# Create deployment directory
mkdir -p /opt/lobechat-deployment
cd /opt

# Clone the official repository
git clone https://github.com/struto-development/lobechat-deployment.git
cd lobechat-deployment
```

## Step 2: Create Required Files

Claude, create the following files with the content from this repository:

1. **docker-compose.yml** - Main orchestration file
2. **.env** - Configuration (copy from .env.example and update)
3. **config/casdoor/app.conf** - Casdoor configuration
4. **config/casdoor/init_data.json** - Initial data
5. **config/nginx/nginx.conf** - Nginx configuration
6. **config/nginx/sites/lobechat.conf** - Site configuration

## Step 3: Configure Environment

Claude, please:

1. **Generate secure passwords:**
```bash
# Generate passwords
POSTGRES_PASS=$(openssl rand -hex 16)
MINIO_PASS=$(openssl rand -hex 16)
KEY_VAULT=$(openssl rand -hex 32)
NEXT_AUTH=$(openssl rand -hex 32)
CASDOOR_SESSION=$(openssl rand -hex 16)
SEARXNG=$(openssl rand -hex 16)

# Display for manual entry or automated update
echo "POSTGRES_PASSWORD=${POSTGRES_PASS}"
echo "MINIO_ROOT_PASSWORD=${MINIO_PASS}"
echo "KEY_VAULTS_SECRET=${KEY_VAULT}"
echo "NEXT_AUTH_SECRET=${NEXT_AUTH}"
echo "CASDOOR_SESSION_SECRET=${CASDOOR_SESSION}"
echo "SEARXNG_SECRET=${SEARXNG}"
```

2. **Update .env file with:**
- Generated passwords
- Domain configuration
- AI provider keys (if available)

## Step 4: Domain Configuration

Claude, update configurations for the target domain:

```bash
# Set domain variable
DOMAIN="example.com"  # Replace with actual domain

# Update .env file
sed -i "s|APP_URL=.*|APP_URL=https://chat.${DOMAIN}|" .env
sed -i "s|AUTH_URL=.*|AUTH_URL=https://chat.${DOMAIN}/api/auth|" .env
sed -i "s|AUTH_CASDOOR_ISSUER=.*|AUTH_CASDOOR_ISSUER=https://auth.${DOMAIN}|" .env
sed -i "s|S3_PUBLIC_DOMAIN=.*|S3_PUBLIC_DOMAIN=https://s3.${DOMAIN}|" .env

# Update nginx configuration
sed -i "s/your-domain.com/${DOMAIN}/g" config/nginx/sites/lobechat.conf

# Update Casdoor redirect URI
jq --arg url "https://chat.${DOMAIN}/api/auth/callback/casdoor" \
   '.applications[1].redirectUris = [$url]' \
   config/casdoor/init_data.json > config/casdoor/init_data.json.tmp && \
   mv config/casdoor/init_data.json.tmp config/casdoor/init_data.json
```

## Step 5: SSL Certificate Setup

### Option A: Let's Encrypt (Recommended)
```bash
# Install certbot if not present
sudo apt-get update && sudo apt-get install -y certbot

# Generate certificates
sudo certbot certonly --standalone \
  -d chat.${DOMAIN} \
  -d auth.${DOMAIN} \
  -d s3.${DOMAIN} \
  --agree-tos \
  --email admin@${DOMAIN} \
  --non-interactive

# Copy certificates
mkdir -p config/nginx/ssl
sudo cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem config/nginx/ssl/chat.${DOMAIN}.crt
sudo cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem config/nginx/ssl/chat.${DOMAIN}.key
# Repeat for auth and s3 subdomains
```

### Option B: Self-Signed (Staging only)
```bash
# Generate self-signed certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout config/nginx/ssl/chat.${DOMAIN}.key \
  -out config/nginx/ssl/chat.${DOMAIN}.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=chat.${DOMAIN}"
# Repeat for auth and s3 subdomains
```

## Step 6: Deploy Services

```bash
# Create necessary directories
mkdir -p data/{postgres,minio,casdoor}

# Stop any existing services
docker compose down 2>/dev/null || true

# Pull latest images
docker compose pull

# Deploy with nginx (production)
docker compose --profile production up -d

# Or deploy without nginx (staging/development)
docker compose up -d

# Wait for services to start
sleep 30

# Check service status
docker compose ps
```

## Step 7: Initialize Casdoor

```bash
# Wait for Casdoor to be ready
for i in {1..30}; do
    if curl -s http://localhost:8000 > /dev/null; then
        echo "Casdoor is ready"
        break
    fi
    echo "Waiting for Casdoor... ($i/30)"
    sleep 2
done

# The init_data.json is automatically loaded on first start
```

## Step 8: Verify Deployment

```bash
# Check all services are running
docker compose ps

# Test LobeChat endpoint
curl -I https://chat.${DOMAIN}/health || curl -I http://localhost:3210/health

# Test Casdoor endpoint
curl -I https://auth.${DOMAIN}/api/health || curl -I http://localhost:8000/api/health

# Test MinIO
docker exec lobe-minio mc ls myminio/

# Check logs for any errors
docker compose logs --tail=50
```

## Step 9: Post-Deployment Configuration

Claude, please inform the user to:

1. **Change default passwords in Casdoor:**
   - Access: https://auth.${DOMAIN}
   - Login with: Organization: `built-in`, Username: `admin`, Password: `admin123`
   - Change admin password immediately
   - Update LobeChat organization users

2. **Configure firewall rules:**
```bash
# Allow only necessary ports
sudo ufw allow 22/tcp  # SSH
sudo ufw allow 80/tcp  # HTTP
sudo ufw allow 443/tcp # HTTPS
sudo ufw enable
```

3. **Set up automated backups:**
```bash
# Create backup script
cat > /opt/lobechat-deployment/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups/lobechat"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p ${BACKUP_DIR}

# Backup database
docker exec lobe-postgres pg_dump -U postgres -d lobe > ${BACKUP_DIR}/lobe_${DATE}.sql
docker exec lobe-postgres pg_dump -U postgres -d casdoor > ${BACKUP_DIR}/casdoor_${DATE}.sql

# Backup MinIO data
docker exec lobe-minio mc mirror myminio/lobe ${BACKUP_DIR}/minio_lobe_${DATE}/

# Keep only last 7 days
find ${BACKUP_DIR} -type f -mtime +7 -delete
EOF

chmod +x /opt/lobechat-deployment/backup.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/lobechat-deployment/backup.sh") | crontab -
```

## Step 10: Monitoring Setup (Optional)

```bash
# Install monitoring stack
docker run -d \
  --name=netdata \
  -p 19999:19999 \
  -v netdataconfig:/etc/netdata \
  -v netdatalib:/var/lib/netdata \
  -v netdatacache:/var/cache/netdata \
  -v /etc/passwd:/host/etc/passwd:ro \
  -v /etc/group:/host/etc/group:ro \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /etc/os-release:/host/etc/os-release:ro \
  --restart unless-stopped \
  --cap-add SYS_PTRACE \
  --security-opt apparmor=unconfined \
  netdata/netdata
```

## Deployment Summary

Claude, after completing deployment, provide this summary to the user:

```
===========================================
LobeChat Deployment Complete!
===========================================

Access URLs:
-----------
LobeChat: https://chat.${DOMAIN}
Casdoor: https://auth.${DOMAIN}
MinIO Console: http://${SERVER_IP}:9001
Monitoring: http://${SERVER_IP}:19999

Default Credentials:
-------------------
Casdoor Admin:
  URL: https://auth.${DOMAIN}
  Organization: built-in
  Username: admin
  Password: admin123 (CHANGE IMMEDIATELY)

LobeChat Users:
  Access via: https://chat.${DOMAIN}
  Configure in Casdoor admin panel

Next Steps:
----------
1. Change all default passwords
2. Configure DNS records for subdomains
3. Test OAuth login flow
4. Add AI provider API keys
5. Set up SSL auto-renewal
6. Configure backup retention

Service Management:
------------------
View logs: docker compose logs -f [service]
Restart: docker compose restart [service]
Stop all: docker compose down
Update: docker compose pull && docker compose up -d

Support:
--------
Logs location: /opt/lobechat-deployment/logs/
Config location: /opt/lobechat-deployment/.env
Backup location: /backups/lobechat/
```

## Troubleshooting Commands

If issues arise, Claude should try:

```bash
# Check service logs
docker compose logs lobe-chat
docker compose logs lobe-casdoor
docker compose logs lobe-postgres

# Restart problematic service
docker compose restart [service-name]

# Check resource usage
docker stats

# Verify network connectivity
docker network ls
docker network inspect lobechat-deployment_lobe-network

# Database connection test
docker exec lobe-postgres pg_isready -U postgres

# Reset everything (WARNING: Data loss)
docker compose down -v
rm -rf data/
docker compose up -d
```

## Notes for Claude Code

- Always verify prerequisites before deployment
- Generate unique passwords for each deployment
- Validate all configuration files before starting services
- Check service logs after deployment for any errors
- Ensure firewall rules are properly configured
- Document any customizations or deviations from standard deployment
- Save all generated passwords securely for the user
- Test all endpoints after deployment to ensure accessibility

## Automated Deployment Function

Claude, you can use this as a reference for full automation:

```bash
#!/bin/bash
# Full automated deployment
deploy_lobechat() {
    local DOMAIN=$1
    local ADMIN_EMAIL=$2

    # All steps from above in sequence
    # With proper error handling
    # And validation at each step

    echo "Deployment complete for ${DOMAIN}"
}

# Usage
deploy_lobechat "example.com" "admin@example.com"
```