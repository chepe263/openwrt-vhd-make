# OpenWrt VHD Converter Pipeline

Automated pipeline to download OpenWrt stable releases and convert them to VHD format (Hyper-V/VirtualBox compatible) with **pre-configured DHCP networking** for immediate VM deployment.

```
┌─────────────────────────┐
│ Step 1: Fetch Metadata  │  Discover current OpenWrt release
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Step 2: Download Image  │  Fetch and verify image file
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ Step 3: Convert to VHD  │  Decompress, configure, convert
└────────────┬────────────┘
             │
             ▼
        🎉 Ready to use in Hyper-V or VirtualBox
```

## Quick Start

```bash
# Run the complete pipeline
chmod +x run-pipeline.sh
./run-pipeline.sh

# Output: /openwrt-vhd-converter/output/*.vhd (ready to use)
```

That's it! The script handles everything:
- ✓ Fetches current stable OpenWrt release
- ✓ Downloads and verifies image integrity
- ✓ Pre-configures networking for DHCP
- ✓ Converts to VHD format
- ✓ All done in ~2 minutes (depending on speed)

## What You Get

After running the pipeline, you'll have:

1. **VHD Image** (`openwrt-vhd-converter/output/*.vhd`)
   - Ready to import into Hyper-V or VirtualBox
   - Pre-configured for DHCP networking
   - Boots directly to a working OpenWrt system
   - No manual configuration needed

2. **Reports** (JSON metadata for each step)
   - `openwrt-release-downloader/download-report.json`
   - `openwrt-vhd-converter/conversion-report.json`

3. **Intermediate Files** (for reference/debugging)
   - Downloaded compressed image (.img.gz)
   - Decompressed raw image (.img)

## Prerequisites

The pipeline requires:
- **Bash shell** (Linux/macOS)
- **Ubuntu/Debian system** (for automatic package installation)
- **sudo access** (to install packages and mount filesystems)
- **~1.5 GB free disk space**

Everything else is installed automatically, including:
- Node.js packages (axios, cheerio)
- System tools (qemu-img, gzip, kpartx, etc.)

## Step-by-Step Breakdown

### Step 1: Fetch Metadata 📋

Located in: `openwrt-release-info-fetcher/fetch-openwrt.js`

**What it does:**
- Discovers current stable OpenWrt release
- Finds all available x86_64 image variants
- Caches metadata for 30 minutes

**Output:** `openwrt-downloads.json`

**Run manually:**
```bash
cd openwrt-release-info-fetcher
npm install
npm run fetch:quiet
```

### Step 2: Download Image ⬇️

Located in: `openwrt-release-downloader/release-downloader.sh`

**What it does:**
- Reads metadata from Step 1
- Downloads `generic-ext4-combined-efi.img.gz` (~13.8 MB)
- Verifies SHA256 checksum against official releases
- Skips re-download if file already valid

**Output:** `openwrt-release-downloader/downloads/*.img.gz` + `download-report.json`

**Run manually:**
```bash
cd openwrt-release-downloader
./release-downloader.sh [--force]
```

### Step 3: Convert to VHD 🔄

Located in: `openwrt-vhd-converter/image-converter.sh`

**What it does:**
- Decompresses .img.gz to raw format
- Mounts raw image and pre-configures WAN for DHCP
- Converts to VHD format (Hyper-V/VirtualBox compatible)
- Generates report with paths and checksums

**Output:** `openwrt-vhd-converter/output/*.vhd` + `conversion-report.json`

**Pre-configured networking:**
- IPv4: eth0 → DHCP
- IPv6: eth0 → DHCPv6
- Loopback: 127.0.0.1

**Run manually:**
```bash
cd openwrt-vhd-converter
./image-converter.sh [--force] [--skip-network-config]
```

## Pipeline Options

### Run with flags

```bash
# Force re-download and re-conversion (bypass caching)
./run-pipeline.sh --force

# Skip network pre-configuration (manual setup later)
./run-pipeline.sh --skip-network-config

# Combine options
./run-pipeline.sh --force --skip-network-config

# Verbose output (show all steps)
./run-pipeline.sh -v
```

### Run individual steps

```bash
# Only update metadata
cd openwrt-release-downloader
npm run fetch

# Only download image
cd openwrt-release-downloader
./release-downloader.sh

# Only convert to VHD
cd openwrt-vhd-converter
./image-converter.sh
```

## Using the VHD

### Hyper-V (Windows)

1. Copy the VHD to your Hyper-V VMs directory
2. Create new VM → Generation 2
3. Connect virtual hard disk → select the VHD
4. Configure networking (usually bridged mode)
5. Start VM → auto-boots to OpenWrt with DHCP IP

### VirtualBox (Linux/macOS/Windows)

1. Open VirtualBox → New VM
2. OS Type: Linux → Linux Kernel
3. Hard Disk: Use existing disk → select the VHD
4. Network: Usually NAT is fine
5. Start VM → auto-boots to OpenWrt with DHCP IP

### First Boot

On first boot, the system will:
1. ✓ Detect new disk/network
2. ✓ Request IP via DHCP (already configured)
3. ✓ Boot to OpenWrt console within ~30 seconds
4. ✓ Ready to configure further or use as-is

**Access OpenWrt:**
```bash
# SSH from host (if DHCP assigned IP)
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@<vm-ip>

# Default credentials
user: root
password: (empty)

# Access LuCI web interface
http://<vm-ip>
```

## Troubleshooting

### "Permission denied" errors
- Ensure you have `sudo` access
- The script needs elevated privileges for mounting filesystems

### "Insufficient disk space"
- Requires ~1.5 GB temporary disk space
- Compressed: 13.8 MB → Decompressed: 120 MB → VHD: 37 MB
- Plus working space for temporary mounts

### Network pre-configuration errors
- Script logs warnings but continues (non-fatal)
- You can still manually configure in VM:
  ```
  vi /etc/config/network
  # Set protocol to 'dhcp'
  /etc/init.d/network restart
  ```
- Or skip with: `./run-pipeline.sh --skip-network-config`

### Download failures
- Check internet connectivity
- Try: `./run-pipeline.sh --force` to re-download
- Manual download: See `openwrt-release-downloader/README.md`

## Project Structure

```
openwrt-vhd-make/
├── README.md (this file)
├── run-pipeline.sh (main entry point)
│
├── openwrt-release-info-fetcher/ (Step 1)
│   ├── fetch-openwrt.js
│   ├── package.json
│   ├── README.md
│   └── openwrt-downloads.json (generated)
│
├── openwrt-release-downloader/ (Step 2)
│   ├── release-downloader.sh
│   ├── downloads/ (generated)
│   ├── download-report.json (generated)
│   └── README.md
│
├── openwrt-vhd-converter/ (Step 3)
│   ├── image-converter.sh
│   ├── output/ (generated VHD files)
│   ├── work/ (generated intermediate files)
│   ├── conversion-report.json (generated)
│   └── README.md
│
└── LICENSE
```

## Pipeline Features

✅ **Fully Automated**
- No manual steps required
- All dependencies auto-installed
- Smart caching to avoid re-downloading

✅ **Reliable**
- SHA256 verification of downloaded files
- Proper error handling and cleanup
- Automatic resource management (mount cleanup on interruption)

✅ **Flexible**
- Optional network pre-configuration
- Can re-run individual steps
- Supports multiple run modes (--force, --skip-network-config, verbose)

✅ **Well-Documented**
- Comprehensive README files
- Detailed scripts with inline comments
- JSON reports for automation/integration

✅ **Production-Ready**
- VHD format compatible with major hypervisors
- Pre-configured DHCP saves setup time
- No manual image mounting or modification

## Current Status

**Pipeline Version**: 1.0  
**OpenWrt Release**: 25.12.4 (stable)  
**Last Updated**: May 22, 2026

### What's Working
- ✓ Metadata fetching with 30-min cache
- ✓ Image download with SHA256 verification
- ✓ Network pre-configuration with DHCP
- ✓ VHD conversion for Hyper-V/VirtualBox
- ✓ Complete pipeline automation

### Future Enhancements
- Step 4: Automated VM creation in Hyper-V/VirtualBox
- Custom OpenWrt configurations
- Pre-install packages/services
- Automatic SSH key injection

## Getting Help

Each step has detailed documentation:
- `openwrt-release-info-fetcher/README.md` — Metadata fetching details
- `openwrt-release-downloader/README.md` — Download and verification
- `openwrt-vhd-converter/README.md` — VHD conversion and networking

## License

See LICENSE file

---

**Ready to go?** Run: `./run-pipeline.sh`
