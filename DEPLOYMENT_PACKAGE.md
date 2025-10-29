# LobeChat Production Deployment Package

## 📦 Package Contents

This deployment package includes everything needed to deploy LobeChat with Casdoor SSO to production or staging servers.

### Complete File List

```
lobechat-deployment/
├── docker-compose.yml              # Main Docker orchestration
├── .env.example                    # Environment configuration template
├── .gitignore                      # Git ignore rules
├── README.md                       # Main documentation
├── CLAUDE_CODE_DEPLOY.md           # Claude Code automation instructions
├── DEPLOYMENT_PACKAGE.md           # This file
│
├── config/
│   ├── casdoor/
│   │   ├── app.conf               # Casdoor runtime configuration
│   │   └── init_data.json         # Initial organizations, users, and apps
│   ├── nginx/
│   │   ├── nginx.conf             # Main nginx configuration
│   │   └── sites/
│   │       └── lobechat.conf      # Site-specific nginx config
│   └── searxng/                   # Search engine config (created at runtime)
│
├── scripts/
│   ├── deploy.sh                  # Automated deployment script
│   ├── backup.sh                  # Backup automation
│   └── restore.sh                 # Restore from backup
│
└── docs/                          # Additional documentation
```

## 🚀 Quick Deployment

### For Manual Deployment

1. **Upload this entire folder to your server:**
```bash
scp -r lobechat-deployment/ user@server:/opt/
```

2. **SSH to server and run:**
```bash
cd /opt/lobechat-deployment
cp .env.example .env
nano .env  # Configure your settings
chmod +x scripts/*.sh
./scripts/deploy.sh
```

### For Claude Code Automated Deployment

1. **Provide Claude Code with:**
   - Server SSH access
   - This deployment package location
   - Target domain name
   - AI provider API keys (optional)

2. **Ask Claude Code to:**
   "Deploy LobeChat using the CLAUDE_CODE_DEPLOY.md instructions to server.example.com with domain chat.example.com"

## 📋 Pre-Deployment Checklist

### Server Requirements
- [ ] Ubuntu 20.04+ or similar Linux distribution
- [ ] Docker Engine 20.10+ installed
- [ ] Docker Compose 2.0+ installed
- [ ] Minimum 4GB RAM
- [ ] Minimum 20GB free disk space
- [ ] Ports 80/443 available

### Domain & DNS
- [ ] Domain name registered
- [ ] DNS A records configured:
  - [ ] `chat.yourdomain.com` → Server IP
  - [ ] `auth.yourdomain.com` → Server IP
  - [ ] `s3.yourdomain.com` → Server IP (optional)

### Security
- [ ] SSH key authentication configured
- [ ] Firewall rules prepared
- [ ] SSL certificates ready or Let's Encrypt available

## 🔑 Configuration Required

### Essential Settings in .env

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN_NAME` | Your base domain | `example.com` |
| `POSTGRES_PASSWORD` | Database password | Generate with `openssl rand -hex 16` |
| `MINIO_ROOT_PASSWORD` | Storage password | Generate with `openssl rand -hex 16` |
| `KEY_VAULTS_SECRET` | Encryption key | Generate with `openssl rand -hex 32` |
| `NEXT_AUTH_SECRET` | Auth secret | Generate with `openssl rand -hex 32` |
| `CASDOOR_SESSION_SECRET` | Session secret | Generate with `openssl rand -hex 16` |

### Optional AI Providers

| Provider | Variable | Where to Get |
|----------|----------|--------------|
| OpenAI | `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| Anthropic | `ANTHROPIC_API_KEY` | https://console.anthropic.com/settings/keys |
| Google | `GEMINI_API_KEY` | https://makersuite.google.com/app/apikey |
| Groq | `GROQ_API_KEY` | https://console.groq.com/keys |

## 🔄 Deployment Workflow

### Phase 1: Preparation (5 minutes)
1. Upload package to server
2. Configure environment variables
3. Set up domain DNS records

### Phase 2: Deployment (10 minutes)
1. Run deployment script
2. Generate SSL certificates
3. Start Docker services
4. Initialize databases

### Phase 3: Verification (5 minutes)
1. Test all endpoints
2. Verify authentication flow
3. Check service health

### Phase 4: Post-Setup (10 minutes)
1. Change default passwords
2. Configure organizations
3. Set up backups
4. Add AI providers

## 🎯 Key Features Included

### Authentication & SSO
- ✅ Casdoor SSO with OAuth2/OIDC
- ✅ Organization dropdown at login
- ✅ Multiple organization support
- ✅ User role management

### Storage & Database
- ✅ PostgreSQL with pgvector for embeddings
- ✅ MinIO S3-compatible storage
- ✅ Automatic backup scripts
- ✅ Data persistence volumes

### Security & Performance
- ✅ Nginx reverse proxy
- ✅ SSL/TLS encryption
- ✅ Rate limiting
- ✅ Health checks
- ✅ Container isolation

### Management Tools
- ✅ Automated deployment script
- ✅ Backup/restore utilities
- ✅ Docker Compose orchestration
- ✅ Service monitoring

## 📊 Service Architecture

```
Internet
    ↓
[Nginx Reverse Proxy]
    ├── chat.domain.com → LobeChat (3210)
    ├── auth.domain.com → Casdoor (8000)
    └── s3.domain.com → MinIO (9000)
         ↓
[Docker Network: lobe-network]
    ├── LobeChat App
    ├── Casdoor Auth
    ├── PostgreSQL DB
    ├── MinIO Storage
    └── SearXNG Search
```

## 🛟 Support Resources

### Documentation
- Main README: [README.md](README.md)
- Claude Deployment: [CLAUDE_CODE_DEPLOY.md](CLAUDE_CODE_DEPLOY.md)
- Environment Template: [.env.example](.env.example)

### Common Commands
```bash
# View service status
docker compose ps

# View logs
docker compose logs -f [service]

# Restart service
docker compose restart [service]

# Stop all services
docker compose down

# Update services
docker compose pull && docker compose up -d

# Backup data
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh backup-file.tar.gz
```

### Troubleshooting Quick Fixes
```bash
# Reset Casdoor initialization
docker exec lobe-casdoor rm /initialized
docker compose restart casdoor

# Clear MinIO buckets
docker exec lobe-minio mc rm -r --force myminio/lobe

# Reset PostgreSQL
docker compose down -v
docker compose up -d

# Check network
docker network inspect lobechat-deployment_lobe-network
```

## ✅ Ready to Deploy!

This package is production-ready and includes:
- All configuration files
- Automated deployment scripts
- Security best practices
- Backup/restore capabilities
- Comprehensive documentation

Deploy with confidence using either manual steps or Claude Code automation.

---
*Package Version: 1.0.0*
*Created: 2024-10-29*
*Tested with: Docker 24.0, Docker Compose 2.21*