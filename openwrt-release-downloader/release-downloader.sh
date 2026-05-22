#!/bin/bash

##############################################################################
# release-downloader.sh
# 
# Step 2: Download OpenWrt image from metadata discovered in Step 1
# 
# This script:
#  1. Reads openwrt-downloads.json from the fetcher (Step 1)
#  2. Extracts the generic-ext4-combined-efi.img.gz URL and checksum
#  3. Downloads the file to ./downloads/ directory
#  4. Verifies file integrity using SHA256 checksum
#  5. Generates download-report.json for Step 3 (image building)
#
# Usage: ./release-downloader.sh [--force]
#
# Options:
#   --force    Force re-download even if file exists with valid checksum
#
##############################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directories - find the fetcher in sibling directories
# Look for fetch-openwrt.js to identify the fetcher directory
FETCHER_DIR=""
for dir in "$SCRIPT_DIR/../openwrt-release-fetcher" "$SCRIPT_DIR/../openwrt-release-info-fetcher" "$SCRIPT_DIR/../playwright-fetcher"; do
  if [[ -f "$dir/fetch-openwrt.js" ]]; then
    FETCHER_DIR="$dir"
    break
  fi
done

if [[ -z "$FETCHER_DIR" ]]; then
  echo "Error: Could not find fetch-openwrt.js in sibling directories"
  echo "  Searched: ../openwrt-release-fetcher, ../openwrt-release-info-fetcher, ../playwright-fetcher"
  exit 1
fi

DOWNLOADS_DIR="$SCRIPT_DIR/downloads"
METADATA_FILE="$FETCHER_DIR/openwrt-downloads.json"
REPORT_FILE="$SCRIPT_DIR/download-report.json"

# Flags
FORCE_DOWNLOAD=${1:-}
if [[ "$FORCE_DOWNLOAD" == "--force" ]]; then
  FORCE_DOWNLOAD=true
else
  FORCE_DOWNLOAD=false
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_ok() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

##############################################################################
# Verify prerequisites and install if missing
##############################################################################

log "Checking prerequisites..."

# Check for jq
if ! command -v jq &> /dev/null; then
  log_warn "jq not found, attempting to install..."
  
  if command -v apt &> /dev/null; then
    log "Running apt update..."
    if sudo apt update; then
      log "Installing jq..."
      if sudo apt install -y jq; then
        log_ok "jq installed successfully"
      else
        log_error "Failed to install jq"
        exit 1
      fi
    else
      log_error "apt update failed"
      exit 1
    fi
  else
    log_error "jq is required but apt is not available (not an Ubuntu/Debian system?)"
    log_error "Please install jq manually"
    exit 1
  fi
fi
log_ok "jq found"

# Check for wget and curl
if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
  log_warn "Neither wget nor curl found, attempting to install wget..."
  
  if command -v apt &> /dev/null; then
    # apt update was likely already done for jq, but run again if needed
    if ! grep -q "^Hit:" /etc/apt/sources.list* 2>/dev/null; then
      log "Running apt update..."
      sudo apt update || true
    fi
    
    log "Installing wget..."
    if sudo apt install -y wget; then
      log_ok "wget installed successfully"
    else
      log_error "Failed to install wget"
      exit 1
    fi
  else
    log_error "wget/curl required but apt not available"
    exit 1
  fi
fi

# Determine download tool (prefer wget, fallback to curl)
DOWNLOAD_TOOL=""
if command -v wget &> /dev/null; then
  DOWNLOAD_TOOL="wget"
elif command -v curl &> /dev/null; then
  DOWNLOAD_TOOL="curl"
fi

if [[ -z "$DOWNLOAD_TOOL" ]]; then
  log_error "No download tool available (wget/curl installation failed)"
  exit 1
fi
log_ok "Using download tool: $DOWNLOAD_TOOL"

##############################################################################
# Verify metadata file exists (and setup Step 1 if needed)
##############################################################################

# Check if metadata file exists
if [[ ! -f "$METADATA_FILE" ]]; then
  log_warn "Metadata file not found: $METADATA_FILE"
  
  # Check if we can find and setup Step 1
  if [[ ! -d "$FETCHER_DIR" ]]; then
    log_error "Could not find fetcher directory: $FETCHER_DIR"
    exit 1
  fi
  
  log "Attempting to setup Step 1: $FETCHER_DIR"
  
  # Check if node_modules exists
  if [[ ! -d "$FETCHER_DIR/node_modules" ]]; then
    log_warn "node_modules not found in $FETCHER_DIR"
    log "Running: cd $FETCHER_DIR && npm install"
    
    if ! (cd "$FETCHER_DIR" && npm install); then
      log_error "npm install failed in $FETCHER_DIR"
      exit 1
    fi
    log_ok "npm install completed"
  fi
  
  # Try to fetch metadata
  log "Running: cd $FETCHER_DIR && npm run fetch:quiet"
  if ! (cd "$FETCHER_DIR" && npm run fetch:quiet); then
    log_error "Failed to fetch metadata from Step 1"
    exit 1
  fi
  log_ok "Metadata fetched"
fi

# Final check: metadata file must exist now
if [[ ! -f "$METADATA_FILE" ]]; then
  log_error "Metadata file still not found: $METADATA_FILE"
  log_error "Something went wrong with Step 1 setup"
  exit 1
fi
log_ok "Found metadata: $METADATA_FILE"

##############################################################################
# Extract download info
##############################################################################

log "Extracting download metadata..."

# Extract URL and checksum for generic-ext4-combined-efi
DOWNLOAD_URL=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .url' "$METADATA_FILE")
EXPECTED_CHECKSUM=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .checksum' "$METADATA_FILE")
FILE_SIZE=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .size' "$METADATA_FILE")
VERSION=$(jq -r '.version' "$METADATA_FILE")

if [[ -z "$DOWNLOAD_URL" ]] || [[ "$DOWNLOAD_URL" == "null" ]]; then
  log_error "Could not extract download URL from metadata"
  exit 1
fi

FILENAME=$(basename "$DOWNLOAD_URL")
FILEPATH="$DOWNLOADS_DIR/$FILENAME"

log_ok "Version: $VERSION"
log_ok "Filename: $FILENAME"
log_ok "Size: $FILE_SIZE"
log_ok "URL: $DOWNLOAD_URL"
log_ok "Expected checksum: $EXPECTED_CHECKSUM"

##############################################################################
# Check if file already exists and is valid
##############################################################################

if [[ -f "$FILEPATH" ]] && [[ "$FORCE_DOWNLOAD" != "true" ]]; then
  log "File already exists: $FILEPATH"
  log "Verifying checksum..."
  
  ACTUAL_CHECKSUM=$(sha256sum "$FILEPATH" | awk '{print $1}')
  
  if [[ "$ACTUAL_CHECKSUM" == "$EXPECTED_CHECKSUM" ]]; then
    log_ok "Checksum verified! File is valid."
    log_warn "Skipping download (use --force to re-download)"
    
    # Generate report for valid existing file
    DOWNLOAD_TIME=$(stat -c %y "$FILEPATH" 2>/dev/null || stat -f "%Sm" "$FILEPATH" 2>/dev/null || echo "unknown")
    
    jq -n \
      --arg version "$VERSION" \
      --arg filename "$FILENAME" \
      --arg filepath "$FILEPATH" \
      --arg url "$DOWNLOAD_URL" \
      --arg checksum "$ACTUAL_CHECKSUM" \
      --arg file_size "$FILE_SIZE" \
      --arg download_time "$DOWNLOAD_TIME" \
      --arg report_time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{
        version: $version,
        filename: $filename,
        filepath: $filepath,
        url: $url,
        checksum: $checksum,
        file_size: $file_size,
        download_time: $download_time,
        report_generated: $report_time,
        status: "verified"
      }' > "$REPORT_FILE"
    
    log_ok "Report generated: $REPORT_FILE"
    exit 0
  else
    log_warn "Checksum mismatch! Expected: $EXPECTED_CHECKSUM"
    log_warn "Got: $ACTUAL_CHECKSUM"
    log "Re-downloading..."
    rm -f "$FILEPATH"
  fi
fi

##############################################################################
# Create downloads directory
##############################################################################

if [[ ! -d "$DOWNLOADS_DIR" ]]; then
  log "Creating downloads directory: $DOWNLOADS_DIR"
  mkdir -p "$DOWNLOADS_DIR"
  log_ok "Directory created"
fi

##############################################################################
# Download file
##############################################################################

log "Downloading $FILENAME..."
log "Destination: $FILEPATH"

if [[ "$DOWNLOAD_TOOL" == "wget" ]]; then
  if ! wget -O "$FILEPATH" "$DOWNLOAD_URL"; then
    log_error "Download failed using wget"
    rm -f "$FILEPATH"
    exit 1
  fi
else
  if ! curl -L -o "$FILEPATH" "$DOWNLOAD_URL"; then
    log_error "Download failed using curl"
    rm -f "$FILEPATH"
    exit 1
  fi
fi

if [[ ! -f "$FILEPATH" ]]; then
  log_error "Downloaded file not found: $FILEPATH"
  exit 1
fi

log_ok "Download complete"

##############################################################################
# Verify checksum
##############################################################################

log "Verifying checksum..."

ACTUAL_CHECKSUM=$(sha256sum "$FILEPATH" | awk '{print $1}')

if [[ "$ACTUAL_CHECKSUM" == "$EXPECTED_CHECKSUM" ]]; then
  log_ok "Checksum verified successfully!"
else
  log_error "Checksum verification failed!"
  log_error "Expected: $EXPECTED_CHECKSUM"
  log_error "Got:      $ACTUAL_CHECKSUM"
  rm -f "$FILEPATH"
  exit 1
fi

##############################################################################
# Generate download report
##############################################################################

log "Generating download report..."

DOWNLOAD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg version "$VERSION" \
  --arg filename "$FILENAME" \
  --arg filepath "$FILEPATH" \
  --arg url "$DOWNLOAD_URL" \
  --arg checksum "$ACTUAL_CHECKSUM" \
  --arg file_size "$FILE_SIZE" \
  --arg download_time "$DOWNLOAD_TIME" \
  '{
    version: $version,
    filename: $filename,
    filepath: $filepath,
    url: $url,
    checksum: $checksum,
    file_size: $file_size,
    download_time: $download_time,
    status: "downloaded"
  }' > "$REPORT_FILE"

log_ok "Report generated: $REPORT_FILE"

##############################################################################
# Summary
##############################################################################

log ""
log_ok "Step 2 Complete: Download successful"
log ""
echo "Summary:"
echo "  Version:       $VERSION"
echo "  File:          $FILENAME"
echo "  Location:      $FILEPATH"
echo "  Size:          $FILE_SIZE"
echo "  Checksum:      $ACTUAL_CHECKSUM"
echo "  Report:        $REPORT_FILE"
echo ""
