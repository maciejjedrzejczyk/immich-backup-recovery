#!/bin/bash

# Immich Backup and Recovery Script
# Simple shell script for backing up and restoring Immich

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-}"
ENV_FILE="${ENV_FILE:-}"
INTERACTIVE_MODE=false

# Prompt for configuration files
prompt_for_files() {
    echo ""
    echo "=== Configuration File Selection ==="
    
    read -p "Docker Compose file name [docker-compose.yml]: " compose_input
    COMPOSE_FILE="${compose_input:-docker-compose.yml}"
    
    read -p "Environment file name [.env]: " env_input
    ENV_FILE="${env_input:-.env}"
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get container names from docker-compose.yml
get_container_names() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker compose file $COMPOSE_FILE not found"
        exit 1
    fi
    
    # Extract container names using yq or fallback to grep/sed
    if command -v yq >/dev/null 2>&1; then
        # Use yq for proper YAML parsing
        SERVER_CONTAINERS=$(yq eval '.services | to_entries | map(select(.key | contains("server") or contains("machine-learning"))) | .[].value.container_name // .[].key' "$COMPOSE_FILE" | tr '\n' ' ')
        POSTGRES_CONTAINER=$(yq eval '.services.database.container_name // "database"' "$COMPOSE_FILE")
    else
        # Fallback to grep/sed parsing
        SERVER_CONTAINERS=""
        
        # Find immich-server container
        SERVER_CONTAINER=$(grep -A 2 "immich-server:" "$COMPOSE_FILE" | grep "container_name:" | sed 's/.*container_name: *\(.*\)/\1/' | head -1)
        if [[ -n "$SERVER_CONTAINER" ]]; then
            SERVER_CONTAINERS="$SERVER_CONTAINER"
        fi
        
        # Find machine-learning container
        ML_CONTAINER=$(grep -A 2 "immich-machine-learning:" "$COMPOSE_FILE" | grep "container_name:" | sed 's/.*container_name: *\(.*\)/\1/' | head -1)
        if [[ -n "$ML_CONTAINER" ]]; then
            SERVER_CONTAINERS="$SERVER_CONTAINERS $ML_CONTAINER"
        fi
        
        # Find database container
        POSTGRES_CONTAINER=$(grep -A 2 "database:" "$COMPOSE_FILE" | grep "container_name:" | sed 's/.*container_name: *\(.*\)/\1/' | head -1)
        if [[ -z "$POSTGRES_CONTAINER" ]]; then
            POSTGRES_CONTAINER="database"
        fi
    fi
    
    # Clean up whitespace
    SERVER_CONTAINERS=$(echo $SERVER_CONTAINERS | xargs)
    
    log_info "Detected server containers: $SERVER_CONTAINERS"
    log_info "Detected postgres container: $POSTGRES_CONTAINER"
}
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker compose file $COMPOSE_FILE not found"
        exit 1
    fi
    
    # Extract volume mappings using yq or fallback to grep/sed
    if command -v yq >/dev/null 2>&1; then
        # Use yq for proper YAML parsing
        DETECTED_UPLOAD_LOCATION=$(yq eval '.services."immich-server".volumes[] | select(. | contains("/data")) | split(":")[0]' "$COMPOSE_FILE" 2>/dev/null | head -1)
        DETECTED_DB_LOCATION=$(yq eval '.services.database.volumes[] | select(. | contains("/var/lib/postgresql/data")) | split(":")[0]' "$COMPOSE_FILE" 2>/dev/null | head -1)
    else
        # Fallback to grep/sed parsing (less reliable but works without yq)
        DETECTED_UPLOAD_LOCATION=$(grep -A 10 "immich-server:" "$COMPOSE_FILE" | grep ":/data" | sed 's/.*- *\(.*\):.*/\1/' | head -1)
        DETECTED_DB_LOCATION=$(grep -A 15 "database:" "$COMPOSE_FILE" | grep ":/var/lib/postgresql/data" | sed 's/.*- *\(.*\):.*/\1/' | head -1)
# Parse docker-compose.yml to extract volume mappings
parse_docker_compose() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker compose file $COMPOSE_FILE not found"
        exit 1
    fi
    
    # Extract volume mappings using yq or fallback to grep/sed
    if command -v yq >/dev/null 2>&1; then
        # Use yq for proper YAML parsing
        DETECTED_UPLOAD_LOCATION=$(yq eval '.services."immich-server".volumes[] | select(. | contains("/data")) | split(":")[0]' "$COMPOSE_FILE" 2>/dev/null | head -1)
        DETECTED_DB_LOCATION=$(yq eval '.services.database.volumes[] | select(. | contains("/var/lib/postgresql/data")) | split(":")[0]' "$COMPOSE_FILE" 2>/dev/null | head -1)
    else
        # Fallback to grep/sed parsing (less reliable but works without yq)
        DETECTED_UPLOAD_LOCATION=$(grep -A 10 "immich-server:" "$COMPOSE_FILE" | grep ":/data" | sed 's/.*- *\(.*\):.*/\1/' | head -1)
        DETECTED_DB_LOCATION=$(grep -A 15 "database:" "$COMPOSE_FILE" | grep ":/var/lib/postgresql/data" | sed 's/.*- *\(.*\):.*/\1/' | head -1)
    fi
    
    # Expand environment variables in paths
    if [[ -n "$DETECTED_UPLOAD_LOCATION" ]]; then
        DETECTED_UPLOAD_LOCATION=$(eval echo "$DETECTED_UPLOAD_LOCATION")
        UPLOAD_LOCATION="$DETECTED_UPLOAD_LOCATION"
        log_info "Detected upload location from compose file: $UPLOAD_LOCATION"
    fi
    
    if [[ -n "$DETECTED_DB_LOCATION" ]]; then
        DETECTED_DB_LOCATION=$(eval echo "$DETECTED_DB_LOCATION")
        DB_DATA_LOCATION="$DETECTED_DB_LOCATION"
        log_info "Detected database location from compose file: $DB_DATA_LOCATION"
    fi
}
# Load environment variables
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file $ENV_FILE not found"
        exit 1
    fi
    
    # Source the env file
    set -a
    source "$ENV_FILE"
    set +a
    
    # Set defaults
    UPLOAD_LOCATION="${UPLOAD_LOCATION:-./library}"
    DB_DATA_LOCATION="${DB_DATA_LOCATION:-./postgres}"
    DB_USERNAME="${DB_USERNAME:-postgres}"
    
    # Parse docker-compose.yml to override with actual volume mappings
    parse_docker_compose
    
    # Get container names
    get_container_names
}

# Check prerequisites
check_prerequisites() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker compose file $COMPOSE_FILE not found"
        exit 1
    fi
    
    if ! docker ps -a --format '{{.Names}}' | grep -q immich_postgres; then
        log_error "Immich containers not found. Please ensure Immich is deployed."
        exit 1
    fi
}

# Create database backup
backup_database() {
    local backup_dir="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/immich_db_backup_$timestamp.sql.gz"
    
    log_info "Creating database backup: $backup_file"
    
    docker exec -t immich_postgres pg_dumpall --clean --if-exists --username="$DB_USERNAME" | gzip > "$backup_file"
    
    if [[ $? -eq 0 ]]; then
        log_info "Database backup completed: $backup_file"
        echo "$backup_file"
    else
        log_error "Database backup failed"
        exit 1
    fi
}

# Backup filesystem
backup_filesystem() {
    local backup_dir="$1"
    local fs_backup_dir="$backup_dir/filesystem"
    
    log_info "Backing up filesystem data..."
    mkdir -p "$fs_backup_dir"
    
    # Convert relative paths to absolute
    local upload_location=$(realpath "$UPLOAD_LOCATION")
    local upload_backup="$fs_backup_dir/upload_location"
    
    log_info "Backing up: $upload_location -> $upload_backup"
    cp -r "$upload_location" "$upload_backup"
    
    log_info "Filesystem backup completed"
    echo "$fs_backup_dir"
}

# Create backup manifest
create_manifest() {
    local backup_dir="$1"
    local db_backup="$2"
    local fs_backup="$3"
    local manifest_file="$backup_dir/backup_manifest.json"
    
    cat > "$manifest_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "immich_version": "${IMMICH_VERSION:-unknown}",
  "database_backup": "$(basename "$db_backup")",
  "filesystem_backup": "$(basename "$fs_backup")",
  "upload_location": "$(realpath "$UPLOAD_LOCATION")",
  "db_data_location": "$(realpath "$DB_DATA_LOCATION")",
  "db_username": "$DB_USERNAME"
}
EOF
    
    log_info "Backup manifest created: $manifest_file"
}

# Perform backup
perform_backup() {
    local backup_location="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="/tmp/immich_backup_$timestamp"
    local archive_name="immich_backup_$timestamp.tar.gz"
    local archive_path="$backup_location/$archive_name"
    
    log_info "Starting Immich backup process..."
    log_info "Temporary backup directory: $backup_dir"
    log_info "Final archive: $archive_path"
    
    mkdir -p "$backup_dir"
    mkdir -p "$backup_location"
    
    # Stop Immich server for consistent backup
    if [[ -n "$SERVER_CONTAINERS" ]]; then
        log_info "Stopping Immich server containers: $SERVER_CONTAINERS"
        docker stop $SERVER_CONTAINERS || true
    fi
    
    # Ensure cleanup on exit
    trap 'log_info "Restarting Immich services..."; if [[ -n "$SERVER_CONTAINERS" ]]; then docker start $SERVER_CONTAINERS; fi; rm -rf "$backup_dir"' EXIT
    
    # Create backups
    local db_backup=$(backup_database "$backup_dir")
    local fs_backup=$(backup_filesystem "$backup_dir")
    
    # Create manifest
    create_manifest "$backup_dir" "$db_backup" "$fs_backup"
    
    # Create compressed archive
    log_info "Creating compressed archive..."
    tar -czf "$archive_path" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    
    log_info "✅ Backup completed successfully: $archive_path"
}

# Extract and validate backup archive
extract_backup() {
    local archive_path="$1"
    local extract_dir="/tmp/immich_restore_$$"
    
    if [[ ! -f "$archive_path" ]]; then
        log_error "Backup archive not found: $archive_path"
        exit 1
    fi
    
    log_info "Extracting backup archive: $archive_path"
    mkdir -p "$extract_dir"
    tar -xzf "$archive_path" -C "$extract_dir"
    
    # Find the backup directory (should be only one)
    local backup_dir=$(find "$extract_dir" -maxdepth 1 -name "immich_backup_*" -type d | head -1)
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Invalid backup archive: no backup directory found"
        rm -rf "$extract_dir"
        exit 1
    fi
    
    if [[ ! -f "$backup_dir/backup_manifest.json" ]]; then
        log_error "Invalid backup archive: manifest file not found"
        rm -rf "$extract_dir"
        exit 1
    fi
    
    echo "$backup_dir"
}

# Restore database
restore_database() {
    local backup_dir="$1"
    local manifest_file="$backup_dir/backup_manifest.json"
    
    local db_backup_file=$(jq -r '.database_backup' "$manifest_file")
    db_backup_file="$backup_dir/$db_backup_file"
    
    if [[ ! -f "$db_backup_file" ]]; then
        log_error "Database backup file not found: $db_backup_file"
        exit 1
    fi
    
    log_info "Stopping all Immich services..."
    docker compose down -v || true
    
    log_info "Starting PostgreSQL container..."
    docker compose create
    docker start "$POSTGRES_CONTAINER"
    
    log_info "Waiting for PostgreSQL to start..."
    sleep 10
    
    log_info "Restoring database from: $db_backup_file"
    gunzip --stdout "$db_backup_file" | \
    sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" | \
    docker exec -i immich_postgres psql --dbname=postgres --username="$DB_USERNAME"
    
    log_info "✅ Database restored successfully"
}

# Restore filesystem
restore_filesystem() {
    local backup_dir="$1"
    local manifest_file="$backup_dir/backup_manifest.json"
    
    local fs_backup_dir=$(jq -r '.filesystem_backup' "$manifest_file")
    fs_backup_dir="$backup_dir/$fs_backup_dir"
    local upload_backup="$fs_backup_dir/upload_location"
    
    if [[ ! -d "$upload_backup" ]]; then
        log_error "Filesystem backup not found: $upload_backup"
        exit 1
    fi
    
    local current_upload_location=$(realpath "$UPLOAD_LOCATION")
    
    log_info "Restoring filesystem: $upload_backup -> $current_upload_location"
    
    # Remove existing data and restore
    if [[ -d "$current_upload_location" ]]; then
        rm -rf "$current_upload_location"
    fi
    
    cp -r "$upload_backup" "$current_upload_location"
    log_info "✅ Filesystem restored successfully"
}

# Test Immich health
test_health() {
    log_info "Testing Immich health..."
    
    # Start all services
    docker compose up -d
    
    log_info "Waiting for services to start..."
    sleep 30
    
    # Check container health
    local containers=("immich_server" "immich_postgres" "immich_redis" "immich_machine_learning")
    for container in "${containers[@]}"; do
        if docker ps --filter "name=$container" --format '{{.Status}}' | grep -q "Up"; then
            log_info "✅ $container is running"
        else
            log_warn "⚠️  $container may not be running properly"
        fi
    done
    
    # Test HTTP endpoint
    if command -v curl >/dev/null 2>&1; then
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:2283/api/server-info/ping" | grep -q "200"; then
            log_info "✅ Immich API is responding"
        else
            log_warn "⚠️  Immich API may not be responding"
        fi
    else
        log_warn "curl not available, skipping API test"
    fi
}

# Perform restore
perform_restore() {
    local backup_location="$1"
    
    # Handle both archive files and directories for backward compatibility
    if [[ -f "$backup_location" && "$backup_location" == *.tar.gz ]]; then
        log_info "Starting Immich restore from archive: $backup_location"
        local backup_dir=$(extract_backup "$backup_location")
        local cleanup_dir=$(dirname "$backup_dir")
    elif [[ -d "$backup_location" ]]; then
        log_info "Starting Immich restore from directory: $backup_location"
        local backup_dir="$backup_location"
        local cleanup_dir=""
    else
        log_error "Backup location not found or invalid: $backup_location"
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required for restore operations. Please install jq."
        exit 1
    fi
    
    # Restore database
    restore_database "$backup_dir"
    
    # Restore filesystem
    restore_filesystem "$backup_dir"
    
    # Test health
    test_health
    
    # Cleanup extracted files if we extracted an archive
    if [[ -n "$cleanup_dir" ]]; then
        rm -rf "$cleanup_dir"
    fi
    
    log_info "✅ Restore completed successfully"
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] <mode> <location>"
    echo ""
    echo "Modes:"
    echo "  backup   - Create backup of Immich data"
    echo "  restore  - Restore Immich from backup"
    echo ""
    echo "Arguments:"
    echo "  location - For backup: destination directory"
    echo "           - For restore: backup archive (.tar.gz) or directory"
    echo ""
    echo "Options:"
    echo "  -i, --interactive       Interactive mode to specify file names"
    echo "  -c, --compose-file FILE Docker compose file (default: docker-compose.yml)"
    echo "  -e, --env-file FILE     Environment file (default: .env)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  COMPOSE_FILE - Docker compose file (overridden by -c option)"
    echo "  ENV_FILE     - Environment file (overridden by -e option)"
    echo ""
    echo "Examples:"
    echo "  # Non-interactive with defaults"
    echo "  $0 backup /path/to/backup/destination"
    echo ""
    echo "  # Non-interactive with custom files"
    echo "  $0 -c compose.prod.yml -e .env.prod backup /backup/dest"
    echo ""
    echo "  # Interactive mode"
    echo "  $0 -i"
    echo "  $0 --interactive backup /backup/dest"
    echo ""
    echo "  # Using environment variables"
    echo "  COMPOSE_FILE=compose.prod.yml ENV_FILE=.env.prod $0 backup /backup/dest"
}

# Main function
main() {
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            -c|--compose-file)
                COMPOSE_FILE="$2"
                shift 2
                ;;
            -e|--env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            backup|restore)
                MODE="$1"
                shift
                ;;
            *)
                if [[ -z "$LOCATION" ]]; then
                    LOCATION="$1"
                    shift
                else
                    log_error "Unknown argument: $1"
                    show_usage
                    exit 1
                fi
                ;;
        esac
    done
    
    # Interactive mode prompts
    if [[ "$INTERACTIVE_MODE" == true ]]; then
        if [[ -z "$COMPOSE_FILE" ]] || [[ -z "$ENV_FILE" ]]; then
            prompt_for_files
        fi
        
        if [[ -z "$MODE" ]]; then
            echo ""
            echo "Select operation mode:"
            echo "  1. backup"
            echo "  2. restore"
            read -p "Enter choice [1-2]: " mode_choice
            case "$mode_choice" in
                1) MODE="backup" ;;
                2) MODE="restore" ;;
                *) log_error "Invalid choice"; exit 1 ;;
            esac
        fi
        
        if [[ -z "$LOCATION" ]]; then
            if [[ "$MODE" == "backup" ]]; then
                read -p "Backup destination directory: " LOCATION
            else
                read -p "Backup archive or directory to restore: " LOCATION
            fi
        fi
    fi
    
    # Set defaults
    COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
    ENV_FILE="${ENV_FILE:-.env}"
    
    # Validate required arguments
    if [[ -z "$MODE" ]] || [[ -z "$LOCATION" ]]; then
        show_usage
        exit 1
    fi
    
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Load environment
    load_env
    
    # Check prerequisites
    check_prerequisites
    
    case "$MODE" in
        backup)
            perform_backup "$LOCATION"
            ;;
        restore)
            perform_restore "$LOCATION"
            ;;
        *)
            log_error "Invalid mode: $MODE"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
