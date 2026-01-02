#!/bin/bash

# Test script to demonstrate restore functionality
# WARNING: This is for demonstration only - do not run on production data

echo "=== Immich Backup and Recovery Tools Test ==="
echo ""

# Check if backup exists
BACKUP_ARCHIVE="/tmp/test_compressed_backup/immich_backup_20260102_163032.tar.gz"

if [[ -f "$BACKUP_ARCHIVE" ]]; then
    echo "✅ Test backup archive found: $BACKUP_ARCHIVE"
    echo ""
    
    echo "📦 Archive size:"
    ls -lh "$BACKUP_ARCHIVE"
    echo ""
    
    echo "📁 Archive contents (first 15 items):"
    tar -tzf "$BACKUP_ARCHIVE" | head -15
    echo ""
    
    echo "📄 Extracting and showing backup manifest:"
    tar -xzf "$BACKUP_ARCHIVE" -C /tmp
    EXTRACTED_DIR=$(tar -tzf "$BACKUP_ARCHIVE" | head -1 | cut -d'/' -f1)
    cat "/tmp/$EXTRACTED_DIR/backup_manifest.json"
    rm -rf "/tmp/$EXTRACTED_DIR"
    echo ""
    
    echo "🔧 To restore from this backup (CAUTION - will replace current data):"
    echo "./immich_backup.sh restore $BACKUP_ARCHIVE"
    echo "or"
    echo "./immich_backup_tool.py restore $BACKUP_ARCHIVE"
    echo ""
    
    echo "📂 For backward compatibility, you can also restore from directories:"
    echo "tar -xzf $BACKUP_ARCHIVE -C /tmp"
    echo "./immich_backup.sh restore /tmp/immich_backup_*"
    echo ""
    
    echo "⚠️  WARNING: Restore will completely replace your current Immich data!"
    echo "Only run restore on test instances or when you want to replace current data."
    
else
    echo "❌ Test backup archive not found. Run backup first:"
    echo "./immich_backup.sh backup /tmp/test_compressed_backup"
fi

echo ""
echo "=== Test Complete ==="
