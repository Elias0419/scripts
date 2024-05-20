#!/bin/bash

# Paths
DB_PATH="/home/rigs/rigs_pos/db/inventory.db"
DATE=$(date +"%Y%m%d")
REMOTE="google_drive:backups"

rclone copy $DB_PATH $REMOTE/inventory_$DATE.db
