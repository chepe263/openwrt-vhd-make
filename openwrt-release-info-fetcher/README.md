# OpenWrt Download Fetcher

A Node.js script that automatically discovers and fetches all available x86_64 image downloads for the current stable OpenWrt release.

## Purpose

This script:
1. Visits https://downloads.openwrt.org/
2. Identifies the current stable OpenWrt release version
3. Navigates to the x86_64 (x86/64) build directory
4. Extracts all available `.img.gz` files with their checksums and metadata
5. Outputs results as JSON for downstream consumption

## Features

- **Automatic version detection**: Finds the current stable release without hardcoding
- **JSON output**: Machine-readable format with all image options
- **Full metadata**: Includes file size, SHA256 checksum, download date, and full URL
- **Pretty printing**: Console output shows all options for quick review
- **Highlights target image**: Specially marks `generic-ext4-combined-efi.img.gz`

## Installation

```bash
npm install
```

This installs:
- `axios` - HTTP client
- `cheerio` - HTML parsing

## Usage

Run the fetcher:

```bash
npm run fetch
```

Or directly:

```bash
node fetch-openwrt.js
```

### Command-line Options

- **`-q, --quiet`** — Suppress console output (write JSON file silently)
- **`-j, --json-only`** — Output JSON to stdout instead of file (for piping)
- **`-f, --force`** — Force fetch even if cache is recent (< 30 min)
- **`--cache-time N`** — Set cache validity time in minutes (default: 30)
- **`-h, --help`** — Show help message

### Examples

```bash
# Interactive mode (default) - shows progress and lists all options
node fetch-openwrt.js

# Quiet mode - for use in step 1 of a pipeline (only writes JSON file)
# Uses cache if available (< 30 min old)
node fetch-openwrt.js --quiet

# Force refresh, ignore cache
node fetch-openwrt.js --quiet --force

# JSON to stdout - for piping to jq or other tools
node fetch-openwrt.js --json-only | jq '.version'

# Extract just the generic-ext4-combined-efi URL
node fetch-openwrt.js --json-only | jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .url'

# Custom cache time (60 minutes)
node fetch-openwrt.js --quiet --cache-time 60
```

## Caching

The script automatically caches results to `openwrt-downloads.json` and checks if the cached data is fresh before fetching:

- **Default cache TTL**: 30 minutes
- **Automatic check**: Every run checks if cache exists and is fresh
- **Cache hit**: If data is fresh, it's reused immediately (no network request)
- **Cache miss**: If cache is stale or missing, fresh data is fetched and cached
- **Force refresh**: Use `--force` or `-f` flag to skip cache and fetch fresh data
- **Custom TTL**: Use `--cache-time N` to set a different cache validity period

This prevents spamming the OpenWrt CDN while still allowing pipeline steps to quickly access download metadata.

### Example: Pipeline with caching

```bash
#!/bin/bash

# Step 1: Fetch OpenWrt downloads (uses cache if < 30 min old)
node fetch-openwrt.js --quiet

# Step 2: Extract metadata for downstream
VERSION=$(jq -r '.version' openwrt-downloads.json)
TARGET_URL=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .url' openwrt-downloads.json)

echo "Using OpenWrt $VERSION"
echo "Download URL: $TARGET_URL"

# Step 3: Pass to next pipeline step
next-step.sh "$TARGET_URL"
```

## Output

The script generates `openwrt-downloads.json` with the following structure:

```json
{
  "timestamp": "2026-05-22T12:34:56.789Z",
  "version": "25.12.4",
  "releaseUrl": "https://downloads.openwrt.org/releases/25.12.4/targets/",
  "x86_64Url": "https://downloads.openwrt.org/releases/25.12.4/targets/x86/64/",
  "imageCount": 10,
  "images": [
    {
      "name": "openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz",
      "size": "13481.9 KB",
      "checksum": "4fe26f6fe313c766cccc1196ac3c449fbabba1a3fa9f2e6b1ce15e057f27c646",
      "date": "Thu May 14 03:12:27 2026",
      "url": "https://downloads.openwrt.org/releases/25.12.4/targets/x86/64/openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz",
      "displayName": "generic-ext4-combined-efi.img.gz"
    },
    ...
  ]
}
```

## Verification

After running the script:

1. **Check the JSON output**:
   ```bash
   cat openwrt-downloads.json | jq '.images | length'
   ```

2. **Verify checksums** (example):
   ```bash
   # Download the requested image
   DOWNLOAD_URL=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .url' openwrt-downloads.json)
   wget "$DOWNLOAD_URL"
   
   # Verify checksum
   EXPECTED_SHA=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .checksum' openwrt-downloads.json)
   echo "$EXPECTED_SHA  openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz" | sha256sum -c -
   ```

3. **List all available images**:
   ```bash
   jq -r '.images[] | .displayName' openwrt-downloads.json
   ```

## Example: Download the generic-ext4-combined-efi image

```bash
# Run the fetcher
npm run fetch

# Extract the URL from JSON
URL=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .url' openwrt-downloads.json)

# Download
wget "$URL"

# Verify checksum
CHECKSUM=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .checksum' openwrt-downloads.json)
echo "$CHECKSUM  $(basename $URL)" | sha256sum -c -
```

## For Pipeline/Step 1 Usage

When using this as step 1 in a multi-step pipeline, use quiet mode for clean integration. The script automatically caches results to avoid redundant fetches:

```bash
#!/bin/bash

# Fetch downloads silently (uses cache if < 30 min old, otherwise fetches fresh)
node fetch-openwrt.js --quiet

# Extract the target image URL for downstream steps
TARGET_URL=$(jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .url' openwrt-downloads.json)

# Pass to next step
echo "Step 1 complete. Download URL: $TARGET_URL"
```

Or if your pipeline prefers JSON piping (and wants to skip local files):

```bash
#!/bin/bash

# Get all metadata via stdout (still uses cache)
VERSION=$(node fetch-openwrt.js --json-only | jq -r '.version')
TARGET_URL=$(node fetch-openwrt.js --json-only | jq -r '.images[] | select(.displayName == "generic-ext4-combined-efi.img.gz") | .url')

echo "Version: $VERSION"
echo "Download URL: $TARGET_URL"
```

Force a refresh if you need the latest data:

```bash
# Force refresh and skip cache
node fetch-openwrt.js --quiet --force
```

## Notes

- The script uses HTTP + HTML parsing (cheerio) for performance and reliability
- **Automatic caching**: Results are cached for 30 minutes by default to avoid spamming the OpenWrt CDN
- **Cache control**: Use `--force` to refresh or `--cache-time N` to set custom TTL
- The script respects OpenWrt's CDN with proper User-Agent headers
- All URLs are HTTPS and come directly from the official OpenWrt site
- No API key or authentication required
- Lightweight dependencies: only axios and cheerio (2 core packages)

## Troubleshooting

**"Could not find stable release link"**
- The OpenWrt site structure may have changed
- Check https://downloads.openwrt.org/ manually to verify the layout

**"No .img.gz files found"**
- The x86_64 directory structure may have changed
- Verify the URL manually: https://downloads.openwrt.org/releases/{version}/targets/x86/64/

**Network errors**
- Verify internet connectivity
- Check if downloads.openwrt.org is accessible
- The CDN may be rate-limiting; wait and retry

## License

ISC
