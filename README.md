# Immich Backup and Recovery Tools

Comprehensive backup and recovery solution for locally deployed Immich instances using Docker Compose.

## Overview

This toolkit provides two implementations for backing up and restoring Immich data:
- **Python script** (`immich_backup_tool.py`) - Full-featured with detailed error handling
- **Shell script** (`immich_backup.sh`) - Lightweight bash implementation

Both tools follow Immich's official backup guidelines and handle:
- PostgreSQL database backups using `pg_dumpall`
- Complete filesystem backup of upload locations
- Dynamic container detection from docker-compose.yml
- Consistent backup ordering (database first, then filesystem)
- Service management during backup/restore operations
- Health checks after restore
- Compressed archive creation for easy storage

## Features

✅ **No hardcoded values** - All paths and container names read from docker-compose.yml and .env files  
✅ **Two modes** - Backup and restore operations  
✅ **Compressed archives** - Creates single .tar.gz files for easy storage and transfer  
✅ **Dynamic container detection** - Automatically detects container names from compose file  
✅ **Consistent backups** - Stops services during backup for data consistency  
✅ **Complete restoration** - Database + filesystem + health verification  
✅ **Backup manifests** - JSON metadata for tracking backup contents  
✅ **Error handling** - Comprehensive validation and error reporting  
✅ **Backward compatibility** - Supports both archive and directory restore formats  

## Prerequisites

- Docker and Docker Compose
- Running Immich instance deployed via docker-compose
- For shell script: `jq` (JSON processor) for restore operations
- For Python script: Python 3.6+ with required packages

### Install Dependencies

**Python script - Set up virtual environment:**
```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # On macOS/Linux
# OR
venv\Scripts\activate     # On Windows

# Install dependencies
pip install -r requirements.txt
```

**Shell script dependencies:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

## Quick Start

### Backup

```bash
# Using Python script
./immich_backup_tool.py backup /path/to/backup/destination

# Using shell script
./immich_backup.sh backup /path/to/backup/destination
```

### Restore

```bash
# Using Python script - from compressed archive
./immich_backup_tool.py restore /path/to/backup/immich_backup_20240101_120000.tar.gz

# Using shell script - from compressed archive
./immich_backup.sh restore /path/to/backup/immich_backup_20240101_120000.tar.gz

# Both tools also support restoring from uncompressed directories (backward compatibility)
./immich_backup.sh restore /path/to/backup/immich_backup_20240101_120000
```

## Detailed Usage

### Backup Operation

The backup process:

1. **Validates environment** - Checks docker-compose.yml, .env, and running containers
2. **Stops Immich services** - Ensures consistent backup (immich_server, immich_machine_learning)
3. **Creates database backup** - Uses `pg_dumpall` with compression
4. **Backs up filesystem** - Copies entire `UPLOAD_LOCATION` directory
5. **Creates manifest** - JSON file with backup metadata
6. **Creates compressed archive** - Single .tar.gz file containing all backup data
7. **Restarts services** - Brings Immich back online

**Backup output:**
```
/backup/destination/immich_backup_20240101_120000.tar.gz
```

**Archive contents:**
```
immich_backup_20240101_120000/
├── backup_manifest.json          # Backup metadata
├── immich_db_backup_20240101_120000.sql.gz  # Compressed database dump
└── filesystem/
    └── upload_location/           # Complete filesystem backup
        ├── library/               # User assets (if storage template enabled)
        ├── upload/                # Uploaded assets
        ├── profile/               # Profile images
        ├── thumbs/                # Thumbnails
        └── encoded-video/         # Transcoded videos
```

### Restore Operation

The restore process:

1. **Validates backup** - Checks manifest and backup files
2. **Extracts archive** - If restoring from .tar.gz file
3. **Stops all services** - `docker compose down -v`
4. **Restores database** - Creates fresh containers and restores DB
5. **Restores filesystem** - Replaces current upload location with backup
6. **Starts services** - `docker compose up -d`
7. **Health checks** - Verifies containers and API endpoints
8. **Cleanup** - Removes temporary extracted files

### Configuration

Both tools automatically read configuration from:

- **docker-compose.yml** - Container definitions and volume mappings
- **.env file** - Environment variables including:
  - `UPLOAD_LOCATION` - Where Immich stores uploaded files
  - `DB_DATA_LOCATION` - PostgreSQL data directory
  - `DB_USERNAME` - Database username (default: postgres)
  - `IMMICH_VERSION` - Immich version tag

### Custom Configuration

You can specify different files:

```bash
# Python script
./immich_backup_tool.py --compose-file custom-compose.yml --env-file custom.env backup /backup/path

# Shell script (environment variables)
COMPOSE_FILE=custom-compose.yml ENV_FILE=custom.env ./immich_backup.sh backup /backup/path
```

## What Gets Backed Up

Based on Immich's official documentation, the tools backup:

### Critical Data (Always backed up)
- **Database** - Complete PostgreSQL dump with all metadata
- **Original assets** - Photos and videos in `upload/` and `library/` folders
- **Profile images** - User avatars in `profile/` folder

### Additional Data (Included in full backup)
- **Thumbnails** - Generated previews in `thumbs/` folder
- **Encoded videos** - Transcoded videos in `encoded-video/` folder
- **ML cache** - Machine learning model cache (Docker volume)

### What's NOT Backed Up
- **PostgreSQL data files** - Only logical dumps are created (safer approach)
- **Temporary files** - System temporary directories
- **Container logs** - Docker container logs

## Safety Features

### Backup Safety
- **Service shutdown** - Prevents data corruption during backup
- **Atomic operations** - Backup completes fully or fails cleanly
- **Validation checks** - Verifies environment before starting
- **Manifest tracking** - Records backup contents and metadata

### Restore Safety
- **Complete reset** - `docker compose down -v` ensures clean state
- **Validation** - Checks backup integrity before restore
- **Health verification** - Tests services after restore
- **Error handling** - Stops on any failure to prevent partial restores

## Troubleshooting

### Common Issues

**"Immich containers not found"**
```bash
# Ensure Immich is running
docker compose ps

# If not running, start it
docker compose up -d
```

**"Database backup failed"**
```bash
# Check if postgres container is running
docker ps | grep postgres

# Check database credentials in .env file
cat .env | grep DB_
```

**"Permission denied"**
```bash
# Make scripts executable
chmod +x immich_backup_tool.py immich_backup.sh

# Check file permissions on backup location
ls -la /path/to/backup/destination
```

**"jq: command not found" (shell script only)**
```bash
# Install jq
brew install jq  # macOS
sudo apt-get install jq  # Ubuntu/Debian
```

### Restore Issues

**"Database restore failed"**
- Ensure PostgreSQL container is running
- Check database credentials match backup manifest
- Verify backup file is not corrupted

**"Filesystem restore failed"**
- Check disk space on target location
- Verify permissions on upload location
- Ensure no processes are using the upload directory

### Health Check Failures

If health checks fail after restore:
```bash
# Check container logs
docker compose logs immich_server
docker compose logs immich_postgres

# Restart services
docker compose restart

# Check API manually
curl http://localhost:2283/api/server-info/ping
```

## Advanced Usage

### Automated Backups

Create a cron job for regular backups:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /path/to/immich_backup.sh backup /backup/destination
```

### Backup Retention

Implement backup rotation:

```bash
#!/bin/bash
# Keep only last 7 backups
find /backup/destination -name "immich_backup_*" -type d -mtime +7 -exec rm -rf {} \;

# Run backup
/path/to/immich_backup.sh backup /backup/destination
```

### Remote Backups

Sync to remote storage:

```bash
# After backup, sync to remote
./immich_backup.sh backup /local/backup
rsync -av /local/backup/ user@remote:/remote/backup/
```

## Testing

Both tools have been designed to work with your running Immich instance. To test:

1. **Create a test backup:**
   ```bash
   ./immich_backup.sh backup /tmp/test_backup
   ```

2. **Verify backup contents:**
   ```bash
   ls -la /tmp/test_backup/immich_backup_*/
   cat /tmp/test_backup/immich_backup_*/backup_manifest.json
   ```

3. **Test restore (CAUTION - this will replace your data):**
   ```bash
   # Only do this on a test instance!
   ./immich_backup.sh restore /tmp/test_backup/immich_backup_*
   ```

## Support

For issues related to:
- **Backup/restore tools** - Check this README and troubleshooting section
- **Immich itself** - Refer to [Immich documentation](https://docs.immich.app/)
- **Docker issues** - Check Docker and Docker Compose documentation

## License

These tools are provided as-is for use with Immich. Follow your organization's backup and data retention policies.
