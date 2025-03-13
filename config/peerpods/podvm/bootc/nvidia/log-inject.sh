#!/bin/bash

TARGET_BASE_DIR="/var/kata-containers"
LOG_FILE="/var/log/gpu-"

# Loop through each directory in the base directory that matches a hex ID pattern
for ((i=0; i<240; i++)); do
    for dir in "$TARGET_BASE_DIR"/*; do
        [[ -d "$dir" && "$(basename "$dir")" =~ ^[0-9a-fA-F]+$ ]] && [[ ! -d "$dir/rootfs/pause" ]] && cp "$LOG_FILE"* "$dir/rootfs/var/log/"
    done
    sleep 2
done
