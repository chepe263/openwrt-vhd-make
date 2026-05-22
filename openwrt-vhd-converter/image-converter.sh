#!/bin/bash

##############################################################################
# image-converter.sh
# 
# Step 3: Convert OpenWrt raw image to VHD format (Hyper-V/VirtualBox compatible)
# 
# This script:
#  1. Checks for qemu-img and gzip (auto-installs on Ubuntu/Debian)
#  2. Reads download-report.json from Step 2
#  3. Decompresses .img.gz to raw .img format
#  4. Pre-configures network for DHCP (unless --skip-network-config)
#  5. Converts raw .img to VHD format using qemu-img
#  6. Generates conversion-report.json for Step 4 (VM creation)
#
# Usage: ./image-converter.sh [options]
#
# Options:
#   --force                Force re-conversion even if VHD already exists
#   --skip-network-config  Skip OpenWrt network pre-configuration (DHCP setup)
#
##############################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${BLUE}[$timestamp]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}✓${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*" >&2
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

# Directories - find the downloader output in sibling directories
DOWNLOADER_DIR=""
for dir in "$SCRIPT_DIR/../openwrt-release-downloader"; do
  if [[ -f "$dir/download-report.json" ]]; then
    DOWNLOADER_DIR="$dir"
    break
  fi
done

if [[ -z "$DOWNLOADER_DIR" ]]; then
  log_error "Could not find download-report.json in sibling directories"
  log_error "  Searched: ../openwrt-release-downloader"
  exit 1
fi

DOWNLOADS_DIR="$DOWNLOADER_DIR/downloads"
DOWNLOAD_REPORT="$DOWNLOADER_DIR/download-report.json"
WORK_DIR="$SCRIPT_DIR/work"
OUTPUT_DIR="$SCRIPT_DIR/output"
CONVERSION_REPORT="$SCRIPT_DIR/conversion-report.json"

# Flags
FORCE_CONVERSION=false
SKIP_NETWORK_CONFIG=false

for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE_CONVERSION=true
      ;;
    --skip-network-config)
      SKIP_NETWORK_CONFIG=true
      ;;
  esac
done

##############################################################################
# Utility Functions
##############################################################################

check_command() {
  if ! command -v "$1" &> /dev/null; then
    return 1
  fi
  return 0
}

install_if_needed() {
  local package=$1
  local command=${2:-$package}  # Command to check (defaults to package name)
  local name=${2:-$package}
  
  if check_command "$command"; then
    log_success "$name found"
    return 0
  fi
  
  log_warn "$name not found, installing..."
  
  # Ensure apt is up to date
  if ! sudo apt update &> /dev/null; then
    log_error "Failed to run apt update. Do you have sudo access?"
    exit 1
  fi
  
  if ! sudo apt install -y "$package" &> /dev/null; then
    log_error "Failed to install $package"
    exit 1
  fi
  
  log_success "$name installed successfully"
}

get_file_size_mb() {
  local filepath=$1
  local size_bytes=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null)
  echo $((size_bytes / 1024 / 1024))
}

get_file_size_gb() {
  local filepath=$1
  local size_bytes=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null)
  echo $((size_bytes / 1024 / 1024 / 1024))
}

##############################################################################
# Network Configuration Functions
##############################################################################

cleanup_mount() {
  # Cleanup function for mount points
  if [[ -n "${MOUNT_DIR:-}" ]] && mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
    log_warn "Cleaning up: unmounting $MOUNT_DIR"
    sudo umount "$MOUNT_DIR" || true
  fi
  
  # Cleanup kpartx mappings
  if [[ -n "${LOOP_DEVICE:-}" ]]; then
    sudo kpartx -d "$LOOP_DEVICE" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
  fi
  
  # Remove temp directory
  if [[ -n "${MOUNT_DIR:-}" ]] && [[ -d "$MOUNT_DIR" ]]; then
    rm -rf "$MOUNT_DIR" || true
  fi
}

trap cleanup_mount EXIT

configure_openwrt_dhcp() {
  local raw_image=$1
  
  log "Pre-configuring OpenWrt network for DHCP..."
  
  MOUNT_DIR=$(mktemp -d)
  trap cleanup_mount EXIT
  
  # Try to mount directly first (for raw filesystems)
  log "  Mounting: $raw_image"
  
  # Try direct mount first
  if sudo mount -o loop,ro "$raw_image" "$MOUNT_DIR" 2>/dev/null; then
    log_success "Image mounted (direct)"
  else
    # If direct mount fails, try with kpartx to map partitions
    log_warn "Direct mount failed, trying kpartx..."
    
    if ! command -v kpartx &> /dev/null; then
      log_error "kpartx not available and direct mount failed"
      rm -rf "$MOUNT_DIR"
      return 1
    fi
    
    LOOP_DEVICE=$(sudo losetup -f)
    if ! sudo losetup "$LOOP_DEVICE" "$raw_image"; then
      log_error "Failed to setup loop device"
      rm -rf "$MOUNT_DIR"
      return 1
    fi
    
    if ! sudo kpartx -a "$LOOP_DEVICE"; then
      log_error "kpartx failed to map partitions"
      sudo losetup -d "$LOOP_DEVICE"
      rm -rf "$MOUNT_DIR"
      return 1
    fi
    
    # Find the root filesystem partition (typically p2, but search for the largest one)
    # First try p2 specifically (common for EFI images with p1=EFI boot)
    LOOP_NAME="${LOOP_DEVICE##*/}"
    if [[ -b "/dev/mapper/${LOOP_NAME}p2" ]]; then
      PART_DEVICE="/dev/mapper/${LOOP_NAME}p2"
      log "  Using partition 2 (root filesystem)"
    else
      # Fallback: find the largest partition
      PART_DEVICE=$(ls -1 /dev/mapper/${LOOP_NAME}p* 2>/dev/null | sort -V | tail -1)
      if [[ -z "$PART_DEVICE" ]]; then
        log_error "No partitions found"
        sudo kpartx -d "$LOOP_DEVICE"
        sudo losetup -d "$LOOP_DEVICE"
        rm -rf "$MOUNT_DIR"
        return 1
      fi
      log "  Using largest available partition: $PART_DEVICE"
    fi
    
    log "  Found partition: $PART_DEVICE"
    if ! sudo mount -o ro "$PART_DEVICE" "$MOUNT_DIR"; then
      log_error "Failed to mount partition"
      sudo kpartx -d "$LOOP_DEVICE"
      sudo losetup -d "$LOOP_DEVICE"
      rm -rf "$MOUNT_DIR"
      return 1
    fi
    
    log_success "Image mounted via kpartx"
  fi
  
  NETWORK_CONFIG="$MOUNT_DIR/etc/config/network"
  
  # Check if WAN is already DHCP configured
  if [[ -f "$NETWORK_CONFIG" ]]; then
    if grep -q "option proto.*'dhcp'" "$NETWORK_CONFIG" && grep -q "config interface.*'wan'" "$NETWORK_CONFIG"; then
      log_warn "WAN already configured for DHCP, skipping"
      sudo umount "$MOUNT_DIR"
      if [[ -n "${LOOP_DEVICE:-}" ]]; then
        sudo kpartx -d "$LOOP_DEVICE" 2>/dev/null || true
        sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
      fi
      rm -rf "$MOUNT_DIR"
      return 0
    fi
    log_success "Network config found"
    # Backup original config
    sudo cp "$NETWORK_CONFIG" "$NETWORK_CONFIG.bak"
    log "  Backing up original config"
  else
    log_warn "Network config not found, will create new one"
  fi
  
  # Need write access to modify/create, remount as read-write
  log "  Remounting as read-write..."
  sudo mount -o remount,rw "$MOUNT_DIR"
  
  # Create DHCP configuration for WAN
  log "  Configuring WAN interface for DHCP..."
  
  # Use a simple approach: replace or add the WAN interface config
  sudo tee "$NETWORK_CONFIG" > /dev/null << 'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'fd12:3456:789a::/48'

config interface 'wan'
	option device 'eth0'
	option proto 'dhcp'

config interface 'wan6'
	option device 'eth0'
	option proto 'dhcpv6'
EOF
  
  log_success "Network config updated for DHCP"
  
  # Unmount and cleanup
  sudo umount "$MOUNT_DIR"
  if [[ -n "${LOOP_DEVICE:-}" ]]; then
    sudo kpartx -d "$LOOP_DEVICE" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    LOOP_DEVICE=""
  fi
  rm -rf "$MOUNT_DIR"
  
  return 0
}

##############################################################################
# Prerequisite Checks
##############################################################################

log "Checking prerequisites..."

# Check for required tools
install_if_needed "gzip" "gzip"
install_if_needed "qemu-utils" "qemu-img"
install_if_needed "multipath-tools" "kpartx (for network pre-configuration)"

log_success "All prerequisites satisfied"

##############################################################################
# Validate Download Report
##############################################################################

log "Reading download report..."

if [[ ! -f "$DOWNLOAD_REPORT" ]]; then
  log_error "Download report not found: $DOWNLOAD_REPORT"
  log_error "Please run Step 2 (release-downloader.sh) first"
  exit 1
fi

# Extract information from download report
DOWNLOADED_FILE=$(jq -r '.filepath' "$DOWNLOAD_REPORT")
ORIGINAL_CHECKSUM=$(jq -r '.checksum' "$DOWNLOAD_REPORT")
VERSION=$(jq -r '.version' "$DOWNLOAD_REPORT")

if [[ ! -f "$DOWNLOADED_FILE" ]]; then
  log_error "Downloaded file not found: $DOWNLOADED_FILE"
  exit 1
fi

log_success "Found download: $(basename "$DOWNLOADED_FILE")"
log_success "Version: $VERSION"

##############################################################################
# Setup Working Directories
##############################################################################

log "Setting up working directories..."

mkdir -p "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

log_success "Working directory: $WORK_DIR"
log_success "Output directory: $OUTPUT_DIR"

##############################################################################
# Decompress Image
##############################################################################

# Determine output filenames
COMPRESSED_FILENAME="${DOWNLOADED_FILE##*/}"  # basename of compressed file
RAW_FILENAME="${COMPRESSED_FILENAME%.gz}"    # remove .gz extension
VHD_FILENAME="${RAW_FILENAME%.img}.vhd"      # replace .img with .vhd

RAW_IMAGE="$WORK_DIR/$RAW_FILENAME"
VHD_IMAGE="$OUTPUT_DIR/$VHD_FILENAME"

# Check if we already have the decompressed image
if [[ -f "$RAW_IMAGE" ]] && [[ "$FORCE_CONVERSION" != "true" ]]; then
  log_success "Decompressed image already exists: $(basename "$RAW_IMAGE")"
else
  log "Decompressing image..."
  log "  Source: $(basename "$DOWNLOADED_FILE")"
  log "  Destination: $(basename "$RAW_IMAGE")"
  
  if ! gzip -dc "$DOWNLOADED_FILE" > "$RAW_IMAGE"; then
    log_error "Failed to decompress image"
    exit 1
  fi
  
  RAW_SIZE=$(get_file_size_mb "$RAW_IMAGE")
  log_success "Decompression complete (${RAW_SIZE} MB)"
fi

##############################################################################
# Configure Network (Optional)
##############################################################################

if [[ "$SKIP_NETWORK_CONFIG" != "true" ]]; then
  if ! configure_openwrt_dhcp "$RAW_IMAGE"; then
    log_warn "Network configuration failed, continuing without it..."
  fi
else
  log_warn "Network configuration skipped (--skip-network-config)"
fi

##############################################################################
# Convert to VHD
##############################################################################

# Check if VHD already exists
if [[ -f "$VHD_IMAGE" ]] && [[ "$FORCE_CONVERSION" != "true" ]]; then
  log_warn "VHD file already exists: $(basename "$VHD_IMAGE")"
  log_warn "Use --force to re-convert"
  VHD_STATUS="existing"
else
  log "Converting to VHD format..."
  log "  Input: $(basename "$RAW_IMAGE")"
  log "  Output: $(basename "$VHD_IMAGE")"
  log "  Format: raw → VHD"
  
  if ! qemu-img convert -f raw -O vpc "$RAW_IMAGE" "$VHD_IMAGE"; then
    log_error "Failed to convert image to VHD format"
    exit 1
  fi
  
  VHD_SIZE=$(get_file_size_mb "$VHD_IMAGE")
  log_success "Conversion complete (${VHD_SIZE} MB)"
  VHD_STATUS="converted"
fi

##############################################################################
# Verify VHD
##############################################################################

log "Verifying VHD image..."

if ! qemu-img info "$VHD_IMAGE" &> /dev/null; then
  log_error "VHD image is invalid or corrupted"
  exit 1
fi

# Get VHD info
VHD_FORMAT=$(qemu-img info "$VHD_IMAGE" | grep "file format" | awk '{print $NF}')
VHD_ACTUAL_SIZE=$(qemu-img info "$VHD_IMAGE" | grep "virtual size" | awk '{print $4, $5}')

log_success "VHD format verified: $VHD_FORMAT"
log_success "VHD virtual size: $VHD_ACTUAL_SIZE"

##############################################################################
# Generate Conversion Report
##############################################################################

log "Generating conversion report..."

REPORT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VHD_FILE_SIZE=$(get_file_size_mb "$VHD_IMAGE")

cat > "$CONVERSION_REPORT" << EOF
{
  "version": "$VERSION",
  "source_file": "$(basename "$DOWNLOADED_FILE")",
  "source_path": "$DOWNLOADED_FILE",
  "source_checksum": "$ORIGINAL_CHECKSUM",
  "decompressed_file": "$(basename "$RAW_IMAGE")",
  "decompressed_path": "$RAW_IMAGE",
  "output_file": "$(basename "$VHD_IMAGE")",
  "output_path": "$VHD_IMAGE",
  "output_format": "vpc (VirtualBox VHD)",
  "file_size_mb": $VHD_FILE_SIZE,
  "virtual_size": "$VHD_ACTUAL_SIZE",
  "status": "$VHD_STATUS",
  "report_generated": "$REPORT_TIMESTAMP"
}
EOF

log_success "Report generated: $(basename "$CONVERSION_REPORT")"

##############################################################################
# Summary
##############################################################################

log ""
log_success "Step 3 Complete: Image conversion successful"
log ""
echo "Summary:" >&2
echo "  Version:        $VERSION" >&2
echo "  Source:         $(basename "$DOWNLOADED_FILE")" >&2
echo "  Decompressed:   $(basename "$RAW_IMAGE")" >&2
echo "  VHD Output:     $(basename "$VHD_IMAGE")" >&2
echo "  VHD Size:       ${VHD_FILE_SIZE} MB" >&2
echo "  Virtual Size:   $VHD_ACTUAL_SIZE" >&2
echo "  Status:         $VHD_STATUS" >&2
echo "  Report:         $(basename "$CONVERSION_REPORT")" >&2
