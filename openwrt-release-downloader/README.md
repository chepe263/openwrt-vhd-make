# OpenWrt Release Downloader

**Step 2** in the pipeline: Download the OpenWrt image from metadata discovered in Step 1.

## Purpose

This script automates the download and verification of OpenWrt releases:

1. Reads metadata from Step 1 (`openwrt-release-info-fetcher/openwrt-downloads.json`)
2. Extracts the `generic-ext4-combined-efi.img.gz` URL and SHA256 checksum
3. Downloads the image file to `./downloads/` directory
4. Verifies file integrity using the official checksum
5. Generates `download-report.json` for the next step in the pipeline

## Prerequisites

- Bash shell (Linux/macOS)
- Ubuntu/Debian system (uses `apt` for package management)
- `sudo` access (for installing missing dependencies)
- Node.js and npm (for Step 1)

The script will automatically:
- Install missing tools (jq, wget)
- Setup Step 1 if needed (npm install + fetch metadata)

## Installation

Simply make the script executable:

```bash
# Make the script executable
chmod +x release-downloader.sh

# Run it - the script will handle all setup
./release-downloader.sh
```

On first run, the script will:
1. Install missing tools (jq, wget) if needed
2. Check Step 1 setup (npm install if node_modules missing)
3. Fetch metadata from OpenWrt website
4. Download the image and verify checksum

## Usage

### Basic download

```bash
./release-downloader.sh
```

This will:
- Check if the file already exists and is valid (skip download if so)
- Download the image if needed
- Verify the checksum
- Generate `download-report.json`

### Force re-download

```bash
./release-downloader.sh --force
```

Ignore existing file and force a fresh download.

### Example pipeline

```bash
#!/bin/bash
set -e

# Step 2: Download image (Step 1 will auto-setup if needed)
echo "Step 2: Downloading image..."
cd openwrt-release-downloader
./release-downloader.sh

# Step 3: Use the downloaded file
echo "Step 3: Building image..."
DOWNLOAD_REPORT=$(cat download-report.json)
IMAGE_PATH=$(echo "$DOWNLOAD_REPORT" | jq -r '.filepath')
echo "Using: $IMAGE_PATH"

# Pass to next step
next-builder.sh "$IMAGE_PATH"
```

## Output Files

### `downloads/openwrt-*.img.gz`
The downloaded OpenWrt image file. Example:
```
downloads/openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz (13.5 MB)
```

### `download-report.json`
Metadata for Step 3. Example:
```json
{
  "version": "25.12.4",
  "filename": "openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz",
  "filepath": "/path/to/downloads/openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz",
  "url": "https://downloads.openwrt.org/releases/25.12.4/targets/x86/64/openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz",
  "checksum": "4fe26f6fe313c766cccc1196ac3c449fbabba1a3fa9f2e6b1ce15e057f27c646",
  "file_size": "13481.9 KB",
  "download_time": "2026-05-22T17:42:15Z",
  "status": "downloaded"
}
```

## Using the Report

Extract information for the next step:

```bash
# Get the file path
IMAGE_PATH=$(jq -r '.filepath' download-report.json)

# Get the version
VERSION=$(jq -r '.version' download-report.json)

# Get the checksum (already verified)
CHECKSUM=$(jq -r '.checksum' download-report.json)

# All at once
jq '{version, filename, filepath, checksum}' download-report.json
```

## Error Handling

The script checks for:
- ✓ Required tools installed (jq, wget/curl) — auto-installs on Ubuntu/Debian
- ✓ Step 1 setup (node_modules, metadata) — auto-setups if needed
- ✓ Valid download URL and checksum extracted
- ✓ Successful download
- ✓ Checksum verification
- ✓ File integrity before use

If any check fails, the script exits with an error message and cleans up partial files.

## Features

- **Smart caching**: Skips download if file already exists with valid checksum
- **Checksum verification**: Ensures downloaded file integrity
- **Colored output**: Easy-to-read progress and status messages
- **JSON output**: Machine-readable report for pipeline integration
- **Force refresh**: Re-download with `--force` flag
- **Error handling**: Fails safely with clear error messages

## Troubleshooting

**"jq is required"** or **"wget/curl required"**
- The script will attempt automatic installation on Ubuntu/Debian systems
- If automatic install fails, ensure you have `sudo` access
- Manual install: `sudo apt update && sudo apt install -y jq wget`

**"Metadata file not found"**
- The script attempts to automatically setup Step 1
- If auto-setup fails, manually run: `cd ../openwrt-release-info-fetcher && npm install && npm run fetch:quiet`
- Then try running the downloader again

**"npm install failed in Step 1"**
- Ensure Node.js and npm are installed: `node --version && npm --version`
- Try manually: `cd ../openwrt-release-info-fetcher && npm install`

**"Checksum verification failed"**
- The file may be corrupted during download
- Use `--force` to re-download and try again
- Check your internet connection

**"Could not extract download URL"**
- The metadata format may have changed
- Verify metadata is valid: `jq '.images[]' ../openwrt-release-fetcher/openwrt-downloads.json`

## License

ISC
