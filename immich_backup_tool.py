#!/usr/bin/env python3
"""
Immich Backup and Recovery Tool
Comprehensive backup and restore solution for Immich instances
"""

import os
import sys
import json
import shutil
import subprocess
import argparse
import time
import tarfile
import tempfile
import re
from pathlib import Path
from datetime import datetime

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install PyYAML>=6.0")
    sys.exit(1)

class ImmichBackupTool:
    def __init__(self, compose_file="docker-compose.yml", env_file=".env"):
        self.compose_file = compose_file
        self.env_file = env_file
        self.env_vars = {}
        self.load_environment()
    
    def load_environment(self):
        """Load environment variables from .env file"""
        if not os.path.exists(self.env_file):
            raise FileNotFoundError(f"Environment file {self.env_file} not found")
        
        with open(self.env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    self.env_vars[key] = value
    
    def parse_docker_compose(self):
        """Parse docker-compose.yml to extract volume mappings"""
        if not os.path.exists(self.compose_file):
            raise FileNotFoundError(f"Docker compose file {self.compose_file} not found")
        
        try:
            with open(self.compose_file, 'r') as f:
                compose_data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            raise RuntimeError(f"Failed to parse docker-compose.yml: {e}")
        
        volumes = {}
        services = compose_data.get('services', {})
        
        # Extract volume mappings from relevant services
        for service_name, service_config in services.items():
            if 'volumes' in service_config:
                for volume in service_config['volumes']:
                    if isinstance(volume, str) and ':' in volume:
                        host_path, container_path = volume.split(':', 1)
                        # Expand environment variables
                        host_path = self.expand_env_vars(host_path)
                        volumes[container_path] = host_path
        
        return volumes
    
    def get_container_names(self):
        """Get container names from docker-compose.yml"""
        try:
            with open(self.compose_file, 'r') as f:
                compose_data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            raise RuntimeError(f"Failed to parse docker-compose.yml: {e}")
        
        containers = {}
        services = compose_data.get('services', {})
        
        for service_name, service_config in services.items():
            container_name = service_config.get('container_name', service_name)
            containers[service_name] = container_name
        
        return containers
    
    def expand_env_vars(self, path):
        """Expand environment variables in path"""
        # Handle ${VAR} and ${VAR:-default} syntax
        def replace_var(match):
            var_expr = match.group(1)
            if ':-' in var_expr:
                var_name, default = var_expr.split(':-', 1)
                return self.get_env_var(var_name, default)
            else:
                return self.get_env_var(var_expr, '')
        
        return re.sub(r'\$\{([^}]+)\}', replace_var, path)
    
    def get_env_var(self, key, default=None):
        """Get environment variable with fallback"""
        return self.env_vars.get(key, default)
    
    def run_command(self, command, check=True, capture_output=False):
        """Execute shell command"""
        print(f"Executing: {command}")
        result = subprocess.run(command, shell=True, check=check, 
                              capture_output=capture_output, text=True)
        if capture_output:
            return result.stdout.strip()
        return result.returncode == 0
    
    def check_docker_compose(self):
        """Check if docker-compose is available and containers exist"""
        if not os.path.exists(self.compose_file):
            raise FileNotFoundError(f"Docker compose file {self.compose_file} not found")
        
        # Check if containers exist
        result = subprocess.run("docker ps -a --format '{{.Names}}' | grep immich", 
                              shell=True, capture_output=True, text=True)
        if "immich_postgres" not in result.stdout:
            raise RuntimeError("Immich containers not found. Please ensure Immich is deployed.")
    
    def get_backup_paths(self):
        """Get all paths that need to be backed up from docker-compose.yml"""
        volumes = self.parse_docker_compose()
        
        # Find the upload location from volume mappings
        upload_location = None
        db_data_location = None
        
        for container_path, host_path in volumes.items():
            if container_path == '/data':  # Immich server data volume
                upload_location = os.path.abspath(host_path)
            elif container_path == '/var/lib/postgresql/data':  # Database volume
                db_data_location = os.path.abspath(host_path)
        
        # Fallback to environment variables if not found in compose file
        if not upload_location:
            upload_location = os.path.abspath(self.get_env_var('UPLOAD_LOCATION', './library'))
        if not db_data_location:
            db_data_location = os.path.abspath(self.get_env_var('DB_DATA_LOCATION', './postgres'))
        
        paths = {
            'upload_location': upload_location,
            'db_data_location': db_data_location,
            'critical_folders': []
        }
        
        # Critical folders within upload location
        critical_folders = ['library', 'upload', 'profile']
        for folder in critical_folders:
            folder_path = os.path.join(upload_location, folder)
            if os.path.exists(folder_path):
                paths['critical_folders'].append(folder_path)
        
        print(f"Detected upload location: {upload_location}")
        print(f"Detected database location: {db_data_location}")
        
        return paths
    
    def create_database_backup(self, backup_dir):
        """Create database backup using pg_dumpall"""
        db_username = self.get_env_var('DB_USERNAME', 'postgres')
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_file = os.path.join(backup_dir, f"immich_db_backup_{timestamp}.sql.gz")
        
        print(f"Creating database backup: {backup_file}")
        
        # Create database dump
        dump_cmd = f"docker exec -t immich_postgres pg_dumpall --clean --if-exists --username={db_username}"
        gzip_cmd = f"gzip > '{backup_file}'"
        full_cmd = f"{dump_cmd} | {gzip_cmd}"
        
        if not self.run_command(full_cmd):
            raise RuntimeError("Database backup failed")
        
        return backup_file
    
    def backup_filesystem(self, backup_dir, paths):
        """Backup filesystem data"""
        print("Backing up filesystem data...")
        
        # Create filesystem backup directory
        fs_backup_dir = os.path.join(backup_dir, "filesystem")
        os.makedirs(fs_backup_dir, exist_ok=True)
        
        # Backup upload location (entire directory)
        upload_backup = os.path.join(fs_backup_dir, "upload_location")
        print(f"Backing up upload location: {paths['upload_location']} -> {upload_backup}")
        shutil.copytree(paths['upload_location'], upload_backup, dirs_exist_ok=True)
        
        return fs_backup_dir
    
    def create_backup_manifest(self, backup_dir, db_backup_file, fs_backup_dir, paths):
        """Create backup manifest with metadata"""
        manifest = {
            'timestamp': datetime.now().isoformat(),
            'immich_version': self.get_env_var('IMMICH_VERSION', 'unknown'),
            'database_backup': os.path.basename(db_backup_file),
            'filesystem_backup': os.path.basename(fs_backup_dir),
            'original_paths': paths,
            'env_vars': self.env_vars
        }
        
        manifest_file = os.path.join(backup_dir, "backup_manifest.json")
        with open(manifest_file, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        print(f"Backup manifest created: {manifest_file}")
        return manifest_file
    
    def backup(self, backup_location):
        """Perform complete backup"""
        print("Starting Immich backup process...")
        
        # Validate environment
        self.check_docker_compose()
        paths = self.get_backup_paths()
        
        # Create temporary backup directory
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        temp_backup_dir = os.path.join(tempfile.gettempdir(), f"immich_backup_{timestamp}")
        archive_name = f"immich_backup_{timestamp}.tar.gz"
        archive_path = os.path.join(backup_location, archive_name)
        
        os.makedirs(temp_backup_dir, exist_ok=True)
        os.makedirs(backup_location, exist_ok=True)
        
        print(f"Temporary backup directory: {temp_backup_dir}")
        print(f"Final archive: {archive_path}")
        
        try:
            # Stop Immich services for consistent backup (keep database running)
            containers = self.get_container_names()
            stop_containers = []
            
            # Stop all containers except database (needed for pg_dumpall)
            for service, container in containers.items():
                if 'database' not in service:
                    stop_containers.append(container)
            
            if stop_containers:
                print(f"Stopping Immich containers: {' '.join(stop_containers)}")
                self.run_command(f"docker stop {' '.join(stop_containers)}")
            
            # Create database backup
            db_backup_file = self.create_database_backup(temp_backup_dir)
            
            # Backup filesystem
            fs_backup_dir = self.backup_filesystem(temp_backup_dir, paths)
            
            # Create manifest
            self.create_backup_manifest(temp_backup_dir, db_backup_file, fs_backup_dir, paths)
            
            # Create compressed archive
            print("Creating compressed archive...")
            with tarfile.open(archive_path, "w:gz") as tar:
                tar.add(temp_backup_dir, arcname=os.path.basename(temp_backup_dir))
            
            print(f"✅ Backup completed successfully: {archive_path}")
            
        finally:
            # Restart Immich services
            if 'stop_containers' in locals() and stop_containers:
                print(f"Restarting Immich services: {' '.join(stop_containers)}")
                self.run_command(f"docker start {' '.join(stop_containers)}")
            
            # Clean up temporary directory
            if os.path.exists(temp_backup_dir):
                shutil.rmtree(temp_backup_dir)
    
    def extract_backup(self, archive_path):
        """Extract backup archive and return backup directory path"""
        if not os.path.exists(archive_path):
            raise FileNotFoundError(f"Backup archive not found: {archive_path}")
        
        print(f"Extracting backup archive: {archive_path}")
        extract_dir = tempfile.mkdtemp(prefix="immich_restore_")
        
        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(extract_dir)
        
        # Find the backup directory (should be only one)
        backup_dirs = [d for d in os.listdir(extract_dir) if d.startswith("immich_backup_")]
        if not backup_dirs:
            shutil.rmtree(extract_dir)
            raise RuntimeError("Invalid backup archive: no backup directory found")
        
        backup_dir = os.path.join(extract_dir, backup_dirs[0])
        
        # Validate manifest exists
        manifest_file = os.path.join(backup_dir, "backup_manifest.json")
        if not os.path.exists(manifest_file):
            shutil.rmtree(extract_dir)
            raise RuntimeError("Invalid backup archive: manifest file not found")
        
        return backup_dir, extract_dir
    def restore_database(self, backup_dir):
        """Restore database from backup"""
        manifest_file = os.path.join(backup_dir, "backup_manifest.json")
        with open(manifest_file, 'r') as f:
            manifest = json.load(f)
        
        db_backup_file = os.path.join(backup_dir, manifest['database_backup'])
        if not os.path.exists(db_backup_file):
            raise FileNotFoundError(f"Database backup file not found: {db_backup_file}")
        
        db_username = self.get_env_var('DB_USERNAME', 'postgres')
        
        print("Stopping all Immich services...")
        containers = self.get_container_names()
        postgres_container = containers.get('database', 'immich_postgres')
        
        self.run_command("docker compose down -v", check=False)
        
        print("Starting PostgreSQL container...")
        self.run_command("docker compose create")
        self.run_command(f"docker start {postgres_container}")
        
        # Wait for PostgreSQL to be ready
        print("Waiting for PostgreSQL to start...")
        time.sleep(10)
        
        # Restore database
        print(f"Restoring database from: {db_backup_file}")
        restore_cmd = f"""gunzip --stdout "{db_backup_file}" | \
sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" | \
docker exec -i immich_postgres psql --dbname=postgres --username={db_username}"""
        
        if not self.run_command(restore_cmd):
            raise RuntimeError("Database restore failed")
        
        print("✅ Database restored successfully")
    
    def restore_filesystem(self, backup_dir):
        """Restore filesystem from backup"""
        manifest_file = os.path.join(backup_dir, "backup_manifest.json")
        with open(manifest_file, 'r') as f:
            manifest = json.load(f)
        
        fs_backup_dir = os.path.join(backup_dir, manifest['filesystem_backup'])
        upload_backup = os.path.join(fs_backup_dir, "upload_location")
        
        if not os.path.exists(upload_backup):
            raise FileNotFoundError(f"Filesystem backup not found: {upload_backup}")
        
        # Get current upload location
        current_upload_location = self.get_env_var('UPLOAD_LOCATION', './library')
        current_upload_location = os.path.abspath(current_upload_location)
        
        print(f"Restoring filesystem: {upload_backup} -> {current_upload_location}")
        
        # Remove existing data and restore
        if os.path.exists(current_upload_location):
            shutil.rmtree(current_upload_location)
        
        shutil.copytree(upload_backup, current_upload_location)
        print("✅ Filesystem restored successfully")
    
    def test_immich_health(self):
        """Test if Immich is working correctly after restore"""
        print("Testing Immich health...")
        
        # Start all services
        self.run_command("docker compose up -d")
        
        # Wait for services to start
        print("Waiting for services to start...")
        time.sleep(30)
        
        # Check container health
        containers = ['immich_server', 'immich_postgres', 'immich_redis', 'immich_machine_learning']
        for container in containers:
            result = self.run_command(f"docker ps --filter name={container} --format '{{{{.Status}}}}'", 
                                    capture_output=True)
            if "Up" not in result:
                print(f"⚠️  Warning: {container} may not be running properly")
            else:
                print(f"✅ {container} is running")
        
        # Test HTTP endpoint with retries
        try:
            import requests
            max_retries = 6
            retry_delay = 10
            
            for attempt in range(1, max_retries + 1):
                try:
                    response = requests.get("http://localhost:2283/api/server/ping", timeout=10)
                    if response.status_code == 200:
                        print("✅ Immich API is responding")
                        break
                    else:
                        print(f"⚠️  Attempt {attempt}/{max_retries}: API returned status {response.status_code}")
                except requests.exceptions.RequestException as e:
                    print(f"⚠️  Attempt {attempt}/{max_retries}: {e}")
                
                if attempt < max_retries:
                    print(f"Waiting {retry_delay} seconds before retry...")
                    time.sleep(retry_delay)
            else:
                print("⚠️  API health check failed after all retries. Check logs: docker logs immich_server")
        except ImportError:
            print("⚠️  requests module not available, skipping API test")
        except Exception as e:
            print(f"⚠️  Could not test API endpoint: {e}")
    
    def restore(self, backup_location):
        """Perform complete restore"""
        # Handle both archive files and directories for backward compatibility
        if os.path.isfile(backup_location) and backup_location.endswith('.tar.gz'):
            print(f"Starting Immich restore from archive: {backup_location}")
            backup_dir, extract_dir = self.extract_backup(backup_location)
        elif os.path.isdir(backup_location):
            print(f"Starting Immich restore from directory: {backup_location}")
            backup_dir = backup_location
            extract_dir = None
            # Validate backup directory
            manifest_file = os.path.join(backup_location, "backup_manifest.json")
            if not os.path.exists(manifest_file):
                raise FileNotFoundError("Invalid backup: manifest file not found")
        else:
            raise FileNotFoundError(f"Backup location not found or invalid: {backup_location}")
        
        try:
            # Restore database
            self.restore_database(backup_dir)
            
            # Restore filesystem
            self.restore_filesystem(backup_dir)
            
            # Test Immich health
            self.test_immich_health()
            
            print("✅ Restore completed successfully")
            
        except Exception as e:
            print(f"❌ Restore failed: {e}")
            raise
        finally:
            # Clean up extracted files if we extracted an archive
            if extract_dir and os.path.exists(extract_dir):
                shutil.rmtree(extract_dir)

def prompt_for_files():
    """Interactively prompt for compose and env file names"""
    print("\n=== Configuration File Selection ===")
    
    compose_file = input(f"Docker Compose file name [docker-compose.yml]: ").strip()
    if not compose_file:
        compose_file = "docker-compose.yml"
    
    env_file = input(f"Environment file name [.env]: ").strip()
    if not env_file:
        env_file = ".env"
    
    return compose_file, env_file

def main():
    parser = argparse.ArgumentParser(description="Immich Backup and Recovery Tool")
    parser.add_argument("mode", nargs='?', choices=["backup", "restore"], help="Operation mode")
    parser.add_argument("location", nargs='?', help="Backup location (for backup: destination directory, for restore: archive file or directory)")
    parser.add_argument("--compose-file", help="Docker compose file path")
    parser.add_argument("--env-file", help="Environment file path")
    parser.add_argument("-i", "--interactive", action="store_true", help="Interactive mode to specify file names")
    
    args = parser.parse_args()
    
    # Interactive mode
    if args.interactive or (not args.mode or not args.location):
        if not args.compose_file or not args.env_file:
            compose_file, env_file = prompt_for_files()
            args.compose_file = args.compose_file or compose_file
            args.env_file = args.env_file or env_file
        
        if not args.mode:
            print("\nSelect operation mode:")
            print("  1. backup")
            print("  2. restore")
            choice = input("Enter choice [1-2]: ").strip()
            args.mode = "backup" if choice == "1" else "restore" if choice == "2" else None
            if not args.mode:
                print("❌ Invalid choice")
                sys.exit(1)
        
        if not args.location:
            if args.mode == "backup":
                args.location = input("Backup destination directory: ").strip()
            else:
                args.location = input("Backup archive or directory to restore: ").strip()
    
    # Set defaults for non-interactive mode
    if not args.compose_file:
        args.compose_file = "docker-compose.yml"
    if not args.env_file:
        args.env_file = ".env"
    
    if not args.mode or not args.location:
        parser.print_help()
        sys.exit(1)
    
    try:
        tool = ImmichBackupTool(args.compose_file, args.env_file)
        
        if args.mode == "backup":
            tool.backup(args.location)
        elif args.mode == "restore":
            tool.restore(args.location)
            
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
