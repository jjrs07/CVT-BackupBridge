#!/bin/bash

# ============================================
# CONFIG
# ============================================
BUCKET="s3://aucera-db-backups-10234/"
MAX_JOBS=3
LOG_DIR="/var/log/s3_uploads"
MAX_RETRIES=3

mkdir -p "$LOG_DIR"

# ============================================
# ADD YOUR FILES HERE
# ============================================
FILES=(
    "/mnt/d/backup/Aurora1_0416.bak"
    "/mnt/d/backup/Aurora2_0416.bak"
    "/mnt/d/backup/Aurora3_0416.bak"
    "/mnt/d/backup/Aurora4_0416.bak"
    "/mnt/d/backup/Aurora5_0416.bak"
    "/mnt/e/backup/Aurora6_0416.bak"
    "/mnt/e/backup/Aurora7_0416.bak"
    "/mnt/e/backup/Aurora8_0416.bak"
    "/mnt/f/backup/Aurora9_0416.bak"
    "/mnt/f/backup/Aurora10_0416.bak"
    "/mnt/g/backup/Aurora11_0416.bak"
    "/mnt/t/backup/Aurora12_0416.bak"
)

# ============================================
# LOGGING FUNCTION
# ============================================
log() {
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] $1"
}

# ============================================
# UPLOAD FUNCTION (runs in background)
# ============================================
upload_file() {
    local file="$1"
    local retry="$2"
    local filename=$(basename "$file")
    local outfile="$LOG_DIR/$filename.log"
    local errfile="$LOG_DIR/$filename.err"
    local statusfile="$LOG_DIR/$filename.status"

    local size_bytes=$(stat -c%s "$file")
    local size_gb=$(awk "BEGIN {printf \"%.2f\", $size_bytes/1024/1024/1024}")

    local retry_label=""
    [ $retry -gt 0 ] && retry_label=" (Retry $retry/$MAX_RETRIES)"
    log "STARTED  | $filename ($size_gb GB)$retry_label"

    local start=$(date +%s)

    aws s3 cp "$file" "$BUCKET" --no-verify-ssl \
        >"$outfile" 2>"$errfile"

    local exit_code=$?
    local end=$(date +%s)
    local duration=$((end - start))
    [ $duration -eq 0 ] && duration=1

    local mbps=$(awk "BEGIN {printf \"%.1f\", ($size_gb*1024*8)/$duration}")
    local duration_mins=$(awk "BEGIN {printf \"%.1f\", $duration/60}")

    if [ $exit_code -eq 0 ]; then
        log "COMPLETE | $filename | Size: $size_gb GB | Duration: $duration_mins mins | Avg Speed: $mbps Mbps"
        echo "SUCCESS" > "$statusfile"
        rm -f "$outfile" "$errfile"
    else
        local err=$(cat "$errfile")
        log "FAILED   | $filename | Attempt $((retry+1))/$MAX_RETRIES | Error: $err"
        echo "FAILED" > "$statusfile"
    fi

    rm -f "$errfile"
}

# ============================================
# MAIN QUEUE LOOP
# ============================================
log "===== S3 Upload Queue Started ====="
log "Total files to upload: ${#FILES[@]}"
log "Max simultaneous uploads: $MAX_JOBS"
log "Destination bucket: $BUCKET"
log "========================================="

completed=0
failed=0

declare -A RETRY_COUNT
declare -A ACTIVE_PIDS   # pid -> filepath

for file in "${FILES[@]}"; do
    RETRY_COUNT["$file"]=0
done

queue=("${FILES[@]}")

while [ ${#queue[@]} -gt 0 ] || [ ${#ACTIVE_PIDS[@]} -gt 0 ]; do

    # Start new uploads if slots are available
    while [ ${#ACTIVE_PIDS[@]} -lt $MAX_JOBS ] && [ ${#queue[@]} -gt 0 ]; do
        file="${queue[0]}"
        queue=("${queue[@]:1}")
        retry=${RETRY_COUNT["$file"]}

        # Clean up old status file before starting
        rm -f "$LOG_DIR/$(basename $file).status"

        upload_file "$file" "$retry" &
        ACTIVE_PIDS[$!]="$file"
    done

    # Check for any finished PIDs
    for pid in "${!ACTIVE_PIDS[@]}"; do
        if ! kill -0 "$pid" 2>/dev/null; then
            file="${ACTIVE_PIDS[$pid]}"
            filename=$(basename "$file")
            statusfile="$LOG_DIR/$filename.status"

            # Wait for status file to be written
            sleep 1
            status=$(cat "$statusfile" 2>/dev/null)

            if [ "$status" = "SUCCESS" ]; then
                ((completed++))
            else
                retry=${RETRY_COUNT["$file"]}
                if [ $retry -lt $MAX_RETRIES ]; then
                    ((retry++))
                    RETRY_COUNT["$file"]=$retry
                    log "RETRYING | $filename | Attempt $retry/$MAX_RETRIES"
                    queue+=("$file")
                else
                    ((failed++))
                    log "GIVING UP | $filename | Max retries ($MAX_RETRIES) reached"
                fi
            fi

            rm -f "$statusfile"
            unset ACTIVE_PIDS[$pid]
        fi
    done

    sleep 5

done

log "========================================="
log "===== Upload Queue Complete ====="
log "Total: ${#FILES[@]} | Completed: $completed | Failed: $failed"
log "========================================="
