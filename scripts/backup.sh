#!/bin/bash

# LobeChat Backup Script
# Creates backups of database and storage

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups/lobechat}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DATE=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Starting LobeChat Backup${NC}"
echo "Timestamp: ${DATE}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Backup PostgreSQL databases
echo "Backing up PostgreSQL databases..."
docker exec lobe-postgres pg_dump -U postgres -d lobe > "${BACKUP_DIR}/lobe_${DATE}.sql"
docker exec lobe-postgres pg_dump -U postgres -d casdoor > "${BACKUP_DIR}/casdoor_${DATE}.sql"
echo "✓ Database backup complete"

# Backup MinIO data
echo "Backing up MinIO storage..."
mkdir -p "${BACKUP_DIR}/minio_${DATE}"
docker exec lobe-minio mc mirror --overwrite myminio/lobe "${BACKUP_DIR}/minio_${DATE}/lobe/" 2>/dev/null || true
docker exec lobe-minio mc mirror --overwrite myminio/casdoor "${BACKUP_DIR}/minio_${DATE}/casdoor/" 2>/dev/null || true
echo "✓ Storage backup complete"

# Backup configuration files
echo "Backing up configuration..."
tar -czf "${BACKUP_DIR}/config_${DATE}.tar.gz" \
    .env \
    docker-compose.yml \
    config/ \
    2>/dev/null || true
echo "✓ Configuration backup complete"

# Create consolidated archive
echo "Creating consolidated backup..."
cd "${BACKUP_DIR}"
tar -czf "lobechat_backup_${DATE}.tar.gz" \
    "lobe_${DATE}.sql" \
    "casdoor_${DATE}.sql" \
    "minio_${DATE}/" \
    "config_${DATE}.tar.gz"

# Cleanup individual files
rm -f "lobe_${DATE}.sql" "casdoor_${DATE}.sql" "config_${DATE}.tar.gz"
rm -rf "minio_${DATE}/"

# Remove old backups
echo "Cleaning old backups (keeping last ${RETENTION_DAYS} days)..."
find "${BACKUP_DIR}" -name "lobechat_backup_*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete

# Calculate backup size
BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/lobechat_backup_${DATE}.tar.gz" | cut -f1)

echo ""
echo -e "${GREEN}Backup Complete!${NC}"
echo "Location: ${BACKUP_DIR}/lobechat_backup_${DATE}.tar.gz"
echo "Size: ${BACKUP_SIZE}"
echo "Retention: ${RETENTION_DAYS} days"