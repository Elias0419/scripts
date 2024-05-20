#!/bin/bash

DB_PATH="/home/rigs/rigs_pos/db/inventory.db"
BACKUP_DIR1="/home/rigs/database_backups"
BACKUP_DIR2="/home/rigs/fallback_rigs_pos"
GITHUB_TOKEN_PATH="/home/rigs/github_token"
REPO_DIR="/home/rigs/github_backup_repo"
DATE=$(date +"%Y%m%d")

cp $DB_PATH $BACKUP_DIR1/inventory_$DATE.db
cp $DB_PATH $BACKUP_DIR2/inventory_$DATE.db

cd $REPO_DIR
git add $DB_PATH
git commit -m "Backup for $DATE"
GITHUB_TOKEN=$(cat $GITHUB_TOKEN_PATH)
git push https://$GITHUB_TOKEN@github.com/Elias0419/rigs_pos.git
