#!/bin/bash

# Directory monitoring script with detailed events
# Usage: ./monitor_dir.sh [directory_path]

DIR="${1:-.}"

if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' does not exist"
    exit 1
fi

echo "Monitoring directory: $DIR"
echo "Press Ctrl+C to stop"
echo "----------------------------------------"

fswatch -r -v -E --event Created --event Updated --event Removed --event Renamed --event MovedFrom --event MovedTo "$DIR"
