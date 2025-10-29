# LobeChat Deployment - Quick Reference for Claude Code

## 🚀 Single Command Deployment

To deploy LobeChat with Casdoor SSO using ngrok tunnels, simply tell Claude Code:

> **"Please deploy LobeChat using the instructions at:**
> **https://raw.githubusercontent.com/struto-development/lobechat-deployment/main/AGENT_DEPLOY.md"**

## What Claude Code Will Do

1. ✅ Verify server prerequisites (Docker, disk space, memory)
2. ✅ Create complete Docker Compose stack
3. ✅ Configure ngrok tunnels with custom domains
4. ✅ Set up Casdoor SSO with organization dropdown
5. ✅ Deploy PostgreSQL with pgvector
6. ✅ Configure MinIO S3 storage
7. ✅ Generate secure passwords
8. ✅ Set up automated backups
9. ✅ Verify all services are running

## Pre-Configured ngrok Domains

The deployment uses these existing ngrok custom domains:
- **LobeChat UI**: `https://strutoai-lobechat.struto.co.uk.ngrok.app`
- **Casdoor Auth**: `https://auth.strutoai-lobechat.struto.co.uk.ngrok.app`

## Default Access Credentials

After deployment, access the system with:

### LobeChat User Access
- **URL**: https://strutoai-lobechat.struto.co.uk.ngrok.app
- **Organization**: `lobechat`
- **Username**: `user`
- **Password**: `user123`

### Casdoor Admin Access
- **URL**: https://auth.strutoai-lobechat.struto.co.uk.ngrok.app
- **Organization**: `built-in`
- **Username**: `admin`
- **Password**: `admin123`

## Required Information

Claude Code only needs:
- **Server SSH access** (with sudo privileges)
- **The instruction URL** (provided above)

Everything else is pre-configured!

## Alternative Deployment Methods

### Method 1: Direct GitHub Clone
```bash
git clone https://github.com/struto-development/lobechat-deployment.git
cd lobechat-deployment
# Follow AGENT_DEPLOY.md instructions
```

### Method 2: Manual with Docker Compose
```bash
# Use the docker-compose.yml and configuration files from the repository
docker compose up -d
```

### Method 3: Custom Domain (without ngrok)
Edit `.env.example` to use your own domain and SSL certificates.

## Repository Links

- **GitHub Repository**: https://github.com/struto-development/lobechat-deployment
- **Agent Instructions**: https://raw.githubusercontent.com/struto-development/lobechat-deployment/main/AGENT_DEPLOY.md
- **Docker Compose**: https://raw.githubusercontent.com/struto-development/lobechat-deployment/main/docker-compose.yml
- **Environment Template**: https://raw.githubusercontent.com/struto-development/lobechat-deployment/main/.env.example

## Features Included

✅ **ngrok Tunnels** - Secure public access without domain setup
✅ **Casdoor SSO** - Organization dropdown and multi-org support
✅ **PostgreSQL + pgvector** - AI embeddings support
✅ **MinIO S3** - Object storage for files
✅ **Automated Backups** - Daily backup with retention
✅ **AI Provider Ready** - Just add API keys
✅ **Production Security** - Firewall, SSL via ngrok, secure defaults

## Support

- **Issues**: https://github.com/struto-development/lobechat-deployment/issues
- **Documentation**: Repository README and docs

---

**Quick Deploy**: Just give Claude Code the instruction URL and server access!