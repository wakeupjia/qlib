#!/bin/bash
# ------------------------------------------------------------
# cron:  0 16-23/2 * * 1-5   (every 2 h, Mon-Fri 16-22)
# ------------------------------------------------------------

# ---------- CONFIG ----------
SCRIPT_DIR="/Users/jiatang/Desktop/projects/qlib/qlib/data_loader"
LOGFILE="$SCRIPT_DIR/update.log"
DATA_DIR="$HOME/.qlib/qlib_data/cn_data"
DOWNLOAD_URL="https://github.com/chenditc/investment_data/releases/latest/download/qlib_bin.tar.gz"
# ----------------------------

# ---- Helper: retry a command (max 3 tries, 10 s delay) ----
retry() {
    local n=1 max=3 delay=10
    while true; do
        "$@" && break || {
            if (( n < max )); then
                ((n++))
                echo "Attempt $n failed: $*"
                sleep $delay
            else
                echo "Command failed after $n attempts: $*"
                return 1
            fi
        }
    done
}

# ---- Helper: quiet logging (only to LOGFILE) ----
log() { echo "[$(date +'%F %T')] $*" >> "$LOGFILE"; }

# -----------------------------------------------------------------
log "=== update run started ==="

# 1. Get today's date (YYYY-MM-DD) and the weekday name
today=$(date +%Y-%m-%d)
weekday=$(date -j -f "%Y-%m-%d" "$today" +%A)   # macOS syntax

# 2. Fetch the latest release tag (with retry)
release_tag=$(retry curl -s https://api.github.com/repos/chenditc/investment_data/releases/latest |
               grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$release_tag" ]]; then
    log "ERROR: Could not fetch latest release tag"
    exit 1
fi

log "Latest release tag: $release_tag  (today: $today)"

# 3. Only proceed if the release is **today's weekday** and we do NOT already have it
if [[ "$release_tag" == "$today" ]]; then
    # Look for a marker file that tells us the data for *this weekday* is already present
    marker="$DATA_DIR/.downloaded_${weekday}"

    if [[ -f "$marker" ]]; then
        log "Already have $weekday data (marker $marker exists). Skipping download."
        exit 0
    fi

    log "New $weekday release found – starting download"

    # 4. Download (quiet, retry built-in + our wrapper)
    if retry wget -q --tries=3 --waitretry=10 -O qlib_bin.tar.gz "$DOWNLOAD_URL"; then
        if [[ ! -s qlib_bin.tar.gz ]]; then
            log "ERROR: Downloaded file is empty"
            rm -f qlib_bin.tar.gz
            exit 1
        fi
    else
        log "ERROR: Download failed after retries"
        rm -f qlib_bin.tar.gz
        exit 1
    fi

    # 5. Extract (retry for safety)
    mkdir -p "$DATA_DIR"
    if ! retry tar -zxvf qlib_bin.tar.gz -C "$DATA_DIR" --strip-components=1; then
        log "ERROR: Extraction failed"
        rm -f qlib_bin.tar.gz
        exit 1
    fi

    # 6. Clean-up & create marker
    rm -f qlib_bin.tar.gz
    touch "$marker"
    log "Update complete – $weekday data stored, marker created"
else
    log "No new release today (latest=$release_tag). Nothing to do."
fi

log "=== update run finished ==="
exit 0