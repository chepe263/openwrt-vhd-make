#!/bin/bash

##############################################################################
# run-pipeline.sh
#
# Complete OpenWrt VHD Converter Pipeline
#
# Executes all three steps in order:
#   1. Fetch metadata from OpenWrt website
#   2. Download and verify image
#   3. Convert to VHD format with DHCP pre-configuration
#
# Usage: ./run-pipeline.sh [options]
#
# Options:
#   --force                 Force re-process all steps (bypass caching)
#   --skip-network-config   Skip DHCP pre-configuration
#   -v, --verbose          Show detailed output from each step
#   -h, --help             Show this help message
#
# Examples:
#   ./run-pipeline.sh                           # Normal run (uses cache)
#   ./run-pipeline.sh --force                   # Force all steps
#   ./run-pipeline.sh --skip-network-config     # Skip network setup
#   ./run-pipeline.sh --force -v                # Force with verbose output
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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Flags
FORCE=false
SKIP_NETWORK_CONFIG=false
VERBOSE=false

# Parse command line arguments
for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE=true
      ;;
    --skip-network-config)
      SKIP_NETWORK_CONFIG=true
      ;;
    -v|--verbose)
      VERBOSE=true
      ;;
    -h|--help)
      grep "^#" "$0" | grep -v "^#!/" | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

##############################################################################
# Logging Functions
##############################################################################

log() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${BLUE}[$timestamp]${NC} $*"
}

log_section() {
  echo ""
  echo -e "${CYAN}╭─────────────────────────────────────╮${NC}"
  echo -e "${CYAN}│${NC} $*"
  echo -e "${CYAN}╰─────────────────────────────────────╯${NC}"
  echo ""
}

log_step() {
  echo -e "${YELLOW}▶${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*"
}

##############################################################################
# Prerequisite Checks
##############################################################################

check_prerequisites() {
  log_section "Checking prerequisites"
  
  # Check bash version
  if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    log_error "Bash 4.0+ required (you have $BASH_VERSION)"
    exit 1
  fi
  log_success "Bash version: $BASH_VERSION"
  
  # Check for common commands
  local required_commands=("bash" "jq" "curl" "git")
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      log_error "$cmd not found"
      exit 1
    fi
  done
  log_success "All required commands available"
  
  # Check directories
  if [[ ! -d "$SCRIPT_DIR/openwrt-release-info-fetcher" ]]; then
    log_error "openwrt-release-info-fetcher directory not found"
    exit 1
  fi
  
  if [[ ! -d "$SCRIPT_DIR/openwrt-release-downloader" ]]; then
    log_error "openwrt-release-downloader directory not found"
    exit 1
  fi
  
  if [[ ! -d "$SCRIPT_DIR/openwrt-vhd-converter" ]]; then
    log_error "openwrt-vhd-converter directory not found"
    exit 1
  fi
  log_success "All pipeline directories found"
}

##############################################################################
# Step 1: Fetch Metadata
##############################################################################

run_step1_fetch_metadata() {
  log_section "Step 1: Fetch OpenWrt Metadata"
  
  local fetcher_dir="$SCRIPT_DIR/openwrt-release-info-fetcher"
  cd "$fetcher_dir" || exit 1
  
  log_step "Discovering current stable OpenWrt release..."
  
  # Build command with options
  local cmd="./fetch-openwrt.js"
  [[ "$FORCE" == "true" ]] && cmd="$cmd --force"
  [[ "$VERBOSE" == "false" ]] && cmd="$cmd --quiet"
  
  if $cmd; then
    log_success "Metadata fetched successfully"
    
    if [[ -f "openwrt-downloads.json" ]]; then
      local version=$(jq -r '.version' openwrt-downloads.json 2>/dev/null || echo "unknown")
      local count=$(jq -r '.imageCount' openwrt-downloads.json 2>/dev/null || echo "?")
      log_success "OpenWrt version: $version ($count image variants)"
    fi
  else
    log_error "Failed to fetch metadata"
    exit 1
  fi
  
  cd "$SCRIPT_DIR" || exit 1
}

##############################################################################
# Step 2: Download Image
##############################################################################

run_step2_download_image() {
  log_section "Step 2: Download OpenWrt Image"
  
  local downloader_dir="$SCRIPT_DIR/openwrt-release-downloader"
  cd "$downloader_dir" || exit 1
  
  log_step "Downloading OpenWrt image..."
  
  # Build command with options
  local cmd="./release-downloader.sh"
  [[ "$FORCE" == "true" ]] && cmd="$cmd --force"
  
  if $cmd; then
    log_success "Image download completed"
    
    if [[ -f "download-report.json" ]]; then
      local version=$(jq -r '.version' download-report.json 2>/dev/null || echo "unknown")
      local size=$(jq -r '.file_size' download-report.json 2>/dev/null || echo "?")
      local status=$(jq -r '.status' download-report.json 2>/dev/null || echo "?")
      log_success "Image: $version ($size) — Status: $status"
    fi
  else
    log_error "Failed to download image"
    exit 1
  fi
  
  cd "$SCRIPT_DIR" || exit 1
}

##############################################################################
# Step 3: Convert to VHD
##############################################################################

run_step3_convert_vhd() {
  log_section "Step 3: Convert to VHD Format"
  
  local converter_dir="$SCRIPT_DIR/openwrt-vhd-converter"
  cd "$converter_dir" || exit 1
  
  log_step "Converting image and pre-configuring network..."
  
  # Build command with options
  local cmd="./image-converter.sh"
  [[ "$FORCE" == "true" ]] && cmd="$cmd --force"
  [[ "$SKIP_NETWORK_CONFIG" == "true" ]] && cmd="$cmd --skip-network-config"
  
  if $cmd; then
    log_success "VHD conversion completed"
    
    if [[ -f "conversion-report.json" ]]; then
      local version=$(jq -r '.version' conversion-report.json 2>/dev/null || echo "unknown")
      local output=$(jq -r '.output_file' conversion-report.json 2>/dev/null || echo "?")
      local size=$(jq -r '.file_size_mb' conversion-report.json 2>/dev/null || echo "?")
      local status=$(jq -r '.status' conversion-report.json 2>/dev/null || echo "?")
      log_success "VHD: $output ($size MB) — Status: $status"
    fi
  else
    log_error "Failed to convert image to VHD"
    exit 1
  fi
  
  cd "$SCRIPT_DIR" || exit 1
}

##############################################################################
# Pipeline Summary
##############################################################################

print_summary() {
  log_section "Pipeline Summary"
  
  echo -e "${GREEN}✓ All steps completed successfully!${NC}"
  echo ""
  
  # Collect information from reports
  local fetcher_dir="$SCRIPT_DIR/openwrt-release-info-fetcher"
  local downloader_dir="$SCRIPT_DIR/openwrt-release-downloader"
  local converter_dir="$SCRIPT_DIR/openwrt-vhd-converter"
  
  if [[ -f "$fetcher_dir/openwrt-downloads.json" ]]; then
    local version=$(jq -r '.version' "$fetcher_dir/openwrt-downloads.json" 2>/dev/null || echo "N/A")
    echo "Version: $version"
  fi
  
  if [[ -f "$downloader_dir/download-report.json" ]]; then
    local size=$(jq -r '.file_size' "$downloader_dir/download-report.json" 2>/dev/null || echo "N/A")
    echo "Downloaded: $size"
  fi
  
  if [[ -f "$converter_dir/conversion-report.json" ]]; then
    local vhd_file=$(jq -r '.output_file' "$converter_dir/conversion-report.json" 2>/dev/null || echo "N/A")
    local vhd_path=$(jq -r '.output_path' "$converter_dir/conversion-report.json" 2>/dev/null || echo "N/A")
    echo "VHD Output: $vhd_file"
    echo "VHD Path: $vhd_path"
  fi
  
  echo ""
  echo -e "${CYAN}Next steps:${NC}"
  echo "  1. Copy the VHD to your Hyper-V or VirtualBox"
  echo "  2. Create a new VM and attach the VHD"
  echo "  3. Boot the VM — OpenWrt will start with DHCP networking"
  echo "  4. Access via SSH or web interface (see README)"
  echo ""
  echo -e "${CYAN}Useful links:${NC}"
  echo "  OpenWrt Documentation: https://openwrt.org/docs"
  echo "  Hyper-V Setup: https://openwrt.org/docs/guide-user/virtualization/hyper-v/start"
  echo "  VirtualBox Setup: https://openwrt.org/docs/guide-user/virtualization/virtualbox/start"
  echo ""
}

##############################################################################
# Error Handling
##############################################################################

error_cleanup() {
  local line=$1
  log_error "Pipeline failed at line $line"
  exit 1
}

trap 'error_cleanup $LINENO' ERR

##############################################################################
# Main Execution
##############################################################################

main() {
  # Header
  echo ""
  echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}    OpenWrt VHD Converter Pipeline (v1.0)           ${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}    Automated OpenWrt → Hyper-V/VirtualBox         ${CYAN}║${NC}"
  echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  # Show options
  if [[ "$FORCE" == "true" ]]; then
    log_warn "Force mode: All steps will be re-processed"
  fi
  
  if [[ "$SKIP_NETWORK_CONFIG" == "true" ]]; then
    log_warn "Network config skipped: Manual setup required"
  fi
  
  if [[ "$VERBOSE" == "true" ]]; then
    log "Verbose output enabled"
  fi
  
  # Run checks and all steps
  check_prerequisites
  run_step1_fetch_metadata
  run_step2_download_image
  run_step3_convert_vhd
  print_summary
}

# Run main function
main "$@"
