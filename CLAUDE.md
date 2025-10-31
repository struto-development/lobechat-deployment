# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LobeChat Enterprise Deployment** - Production-ready Docker Compose deployment of LobeChat with Casdoor SSO authentication, PostgreSQL database, MinIO S3 storage, and optional ngrok tunnels for public access.

**Deployment Model**: Infrastructure-as-Code using Docker Compose with two deployment approaches:
1. **Automated Installation**: One-line installation script (`install.sh`) with interactive port configuration
2. **Agent-Guided Deployment**: AI-assisted deployment via `AGENT_DEPLOY.md` instructions

**Technology Stack**:
- **Application**: LobeChat (lobehub/lobe-chat-database)
- **Authentication**: Casdoor v2.13.0 (SSO with organization dropdown)
- **Database**: PostgreSQL 17 with pgvector extension
- **Storage**: MinIO (S3-compatible object storage)
- **Search**: SearXNG (optional)
- **Proxy**: Nginx (production profile)
- **Tunneling**: ngrok with custom domains

## Development Commands

### Deployment & Management

```bash
# Quick installation to default location (~/lobechat)
bash install.sh

# Quick installation to custom location
bash install.sh /custom/path

# Or use environment variable
INSTALL_DIR=/custom/path bash install.sh

# Manual deployment without nginx
docker compose up -d

# Manual deployment with nginx (production profile)
docker compose --profile production up -d

# View all service logs
docker compose logs -f

# View specific service logs
docker compose logs -f [lobe|casdoor|postgresql|minio]

# Stop all services
docker compose down

# Stop and remove volumes (destructive)
docker compose down -v
```

### Service Management

```bash
# Restart specific service
docker compose restart [service-name]

# Check service status
docker compose ps

# Pull latest images
docker compose pull

# Recreate containers with latest images
docker compose up -d --force-recreate
```

### Database Operations

```bash
# Create lobe database (critical for preventing migration errors)
docker exec lobe-postgres psql -U postgres -c "CREATE DATABASE lobe;"

# Check database connectivity
docker exec lobe-postgres pg_isready -U postgres

# List databases
docker exec lobe-postgres psql -U postgres -c "\l"

# Access PostgreSQL shell
docker exec -it lobe-postgres psql -U postgres -d lobe
```

### Backup & Restore

```bash
# Run backup manually
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh backup-YYYYMMDD_HHMMSS.tar.gz

# Manual database backup
docker exec lobe-postgres pg_dump -U postgres -d lobe > lobe_backup.sql
docker exec lobe-postgres pg_dump -U postgres -d casdoor > casdoor_backup.sql
```

### Health Checks & Troubleshooting

```bash
# Check Casdoor initialization status
docker exec lobe-casdoor ls -la /initialized

# Test ngrok tunnel status
docker exec lobe-ngrok wget -O - http://localhost:4040/api/tunnels

# Check for LobeChat errors
docker logs lobe-chat 2>&1 | tail -50 | grep -i error

# Verify MinIO buckets
docker exec lobe-minio mc ls myminio/

# Test service endpoints
curl -I http://localhost:3210  # LobeChat
curl -I http://localhost:8000  # Casdoor
```

## Architecture & Key Components

### Service Architecture

**Network Strategy**: Uses `network_mode: 'service:network-service'` pattern where all services share a single network namespace through an Alpine container. This eliminates inter-container networking overhead and allows `localhost` communication between services.

**Critical Startup Sequence**:
1. PostgreSQL starts with healthcheck
2. Create `lobe` database (MUST happen before LobeChat starts)
3. MinIO starts and auto-creates `lobe` and `casdoor` buckets
4. Casdoor starts, depends on PostgreSQL healthcheck
5. LobeChat starts, depends on PostgreSQL + Casdoor + MinIO
6. ngrok starts last, depends on LobeChat + Casdoor

### Configuration Management

**Environment Variables** (`.env`):
- Generated passwords: POSTGRES_PASSWORD, MINIO_ROOT_PASSWORD
- Security keys: KEY_VAULTS_SECRET, NEXT_AUTH_SECRET, CASDOOR_SESSION_SECRET (all generated via `openssl rand`)
- Application URLs: APP_URL, AUTH_URL, AUTH_CASDOOR_ISSUER (ngrok domains or custom domains)
- OAuth credentials: Fixed AUTH_CASDOOR_ID and AUTH_CASDOOR_SECRET in init_data.json

**Casdoor Configuration**:
- `config/casdoor/app.conf`: Casdoor runtime configuration (httpport, runmode, session settings)
- `config/casdoor/init_data.json`: Initial data with organizations, applications, users, certs, providers
  - Contains two organizations: `built-in` (system) and `lobechat` (application)
  - OAuth redirect URI must match `APP_URL/api/auth/callback/casdoor`
  - Includes embedded x509 certificate and RSA private key for JWT signing
  - Organization dropdown enabled via `orgChoiceMode: "select"`

**Port Configuration**: The `install.sh` script prompts for a starting port number (e.g., 3000) and automatically assigns 8 consecutive ports:
- PORT_LOBECHAT (starting port + 0)
- PORT_CASDOOR (starting port + 1)
- PORT_MINIO_API (starting port + 2)
- PORT_MINIO_CONSOLE (starting port + 3)
- PORT_POSTGRES (starting port + 4)
- PORT_EXTRA_1/2/3 for metrics/observability (starting port + 5, 6, 7)

### Critical Implementation Details

**Database Initialization Bug Fix**: LobeChat expects the `lobe` database to exist but the docker-compose only creates the `casdoor` database. The installation script explicitly creates the `lobe` database after PostgreSQL starts to prevent migration errors.

**MinIO Bucket Creation**: MinIO container uses a command script that:
1. Starts MinIO server in background
2. Waits 10 seconds for startup
3. Configures mc alias
4. Creates `lobe` and `casdoor` buckets with public anonymous access
5. Uses `-p` flag to prevent errors if buckets exist

**Casdoor Initialization**: Casdoor container checks for `/initialized` marker file. If absent, it waits 5 seconds then POSTs `init_data.json` to `/api/init-data` endpoint and creates the marker. This is idempotent but can fail silently if Casdoor isn't fully ready.

**ngrok Integration**:
- Configuration in `ngrok.yml` with auth token and tunnel definitions
- Two tunnels: `lobechat-ui` (port 3210) and `casdoor-auth` (port 8000)
- Custom domains: `strutoai-lobechat.struto.co.uk.ngrok.app` and `auth.strutoai-lobechat.struto.co.uk.ngrok.app`
- Tunnel status available at `http://localhost:4040/api/tunnels`

## File Structure & Purpose

```
.
├── docker-compose.yml          # Main orchestration (8 services with shared network)
├── .env.example               # Environment template with placeholder values
├── install.sh                 # One-line installation with port configuration
├── README.md                  # User-facing documentation
├── AGENT_DEPLOY.md            # Step-by-step AI agent deployment guide
├── DEPLOY_REFERENCE.md        # Quick reference for manual deployment
├── config/
│   ├── casdoor/
│   │   ├── app.conf           # Casdoor server configuration
│   │   └── init_data.json     # Organizations, apps, users, certs (with OAuth redirect URIs)
│   └── nginx/
│       ├── nginx.conf         # Main nginx config (production profile)
│       └── sites/             # Virtual host configurations
└── scripts/
    ├── deploy.sh              # Interactive deployment script
    ├── backup.sh              # Automated backup (cron: 0 2 * * *)
    └── restore.sh             # Restore from backup archive
```

## Common Workflows & Patterns

### Adding New Services

When adding services to docker-compose.yml:
1. Use `network_mode: 'service:network-service'` to join shared namespace
2. Add port mappings to `network-service` ports section
3. Configure service to bind to specific port (not 0.0.0.0)
4. Update health checks if service is a dependency
5. Add backup logic to `scripts/backup.sh` if service has persistent data

### Modifying OAuth Configuration

To change OAuth redirect URIs:
1. Update `redirectUris` in `config/casdoor/init_data.json` (applications array)
2. Ensure URI matches `${APP_URL}/api/auth/callback/casdoor` format
3. If Casdoor already initialized, delete `/initialized` marker and restart
4. Or manually update via Casdoor admin UI after deployment

### Port Conflicts Resolution

If ports are already in use:
1. Run `install.sh` and specify a different starting port when prompted
2. Or manually edit `docker-compose.yml` port mappings
3. Update `.env` with new port assignments if needed
4. Restart affected services: `docker compose up -d`

### Security Key Rotation

To regenerate security keys:
1. Stop services: `docker compose down`
2. Generate new keys: `openssl rand -hex 32`
3. Update `.env` with new KEY_VAULTS_SECRET, NEXT_AUTH_SECRET, CASDOOR_SESSION_SECRET
4. Restart services: `docker compose up -d`
5. All sessions will be invalidated (users must re-login)

## Important Constraints & Gotchas

1. **macOS Docker File Sharing**: On macOS, Docker Desktop only allows mounting from specific directories by default (`/Users`, `/tmp`, `/private`, etc.). The script now defaults to `~/lobechat` which works out of the box. If you need to use `/opt` or other locations, add them in Docker Desktop → Settings → Resources → File Sharing.

2. **Installation Location**: Default is `~/lobechat` (no sudo required). Can be customized via:
   - Command line: `bash install.sh /custom/path`
   - Environment variable: `INSTALL_DIR=/custom/path bash install.sh`

3. **Database Creation Timing**: The `lobe` database MUST be created after PostgreSQL starts but before LobeChat initializes. If LobeChat starts without this database, it will fail with migration errors.

4. **Shared Network Namespace**: All services communicate via `localhost` within the shared network namespace. This means Casdoor config must use `localhost:5432` not `postgresql:5432`.

5. **Casdoor Initialization Race**: The Casdoor initialization can fail if the container tries to POST init data before Casdoor's HTTP server is ready. The script waits 5 seconds but may need adjustment for slower systems.

6. **ngrok Domain Limitations**: Only one active ngrok instance can use the custom domains at a time. Running multiple deployments with the same ngrok.yml will cause tunnel conflicts.

7. **OAuth Redirect URI Matching**: The redirect URI in Casdoor init_data.json MUST exactly match the callback URL LobeChat expects. Any mismatch causes OAuth failures with generic error messages.

8. **MinIO Anonymous Access**: The deployment sets `mc anonymous set public` on buckets for development convenience. For production, configure proper bucket policies and access keys.

9. **Port Range Requirements**: Installation requires 8 consecutive available ports. The script checks for conflicts but only warns; ports may still conflict with services not detected by `ss` or `netstat`.

10. **Backup Cron Job**: The installation script adds a cron job for backups. Multiple installations will create duplicate cron entries unless cleaned up manually.

## Testing & Validation

### Post-Deployment Checks

```bash
# Verify all containers running
docker compose ps | grep -c "Up" # Should show 6+ services

# Check database tables exist
docker exec lobe-postgres psql -U postgres -d lobe -c "\dt"
docker exec lobe-postgres psql -U postgres -d casdoor -c "\dt"

# Verify MinIO buckets
docker exec lobe-minio mc ls myminio/ | grep -E "lobe|casdoor"

# Test OAuth discovery endpoint
curl https://auth.strutoai-lobechat.struto.co.uk.ngrok.app/.well-known/openid-configuration

# Check LobeChat health
curl http://localhost:3210/api/health
```

### Smoke Tests

1. Access LobeChat UI at ngrok URL
2. Click sign in, verify Casdoor login page loads
3. Select "lobechat" organization from dropdown
4. Login with admin/admin123 credentials
5. Verify redirect back to LobeChat after authentication
6. Check that user profile shows in LobeChat
7. Test file upload (validates MinIO S3 integration)

## Default Credentials (Change Immediately)

**Casdoor System Admin**:
- URL: `https://auth.strutoai-lobechat.struto.co.uk.ngrok.app`
- Organization: `built-in`
- Username: `admin`
- Password: `admin123`

**LobeChat Admin**:
- URL: `https://strutoai-lobechat.struto.co.uk.ngrok.app`
- Organization: `lobechat`
- Username: `admin`
- Password: `admin123`

**LobeChat Demo User**:
- Organization: `lobechat`
- Username: `user`
- Password: `user123`

**MinIO**:
- Console: `http://localhost:9001`
- Username: `minioadmin`
- Password: Set in `.env` as `MINIO_ROOT_PASSWORD`
