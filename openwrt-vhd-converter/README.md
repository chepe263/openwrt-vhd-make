# OpenWrt VHD Image Converter (Step 3)

Convert OpenWrt raw images to VHD format (Hyper-V/VirtualBox compatible).

## Overview

This script automates the conversion of OpenWrt x86_64 generic images from compressed format to Virtual Hard Disk (VHD) format. VHD is compatible with:
- Microsoft Hyper-V
- Oracle VirtualBox
- Other VHD-capable hypervisors

The script handles:
- ✓ Decompression of .img.gz files to raw .img format
- ✓ Conversion from raw to VHD (hypervisor-compatible) format
- ✓ Verification of output VHD image integrity
- ✓ Caching of intermediate and final outputs
- ✓ JSON report generation for pipeline integration

## Prerequisites

The script automatically installs on Ubuntu/Debian:
- `qemu-img` (QEMU image utilities) — for format conversion
- `gzip` (if not available) — for decompression
- `kpartx` (multipath-tools) — for mounting partitioned images to pre-configure network

**Note**: VirtualBox/Hyper-V are NOT needed for image conversion, only when *using* the VHD file with those hypervisors.

## Installation

Simply make the script executable:

```bash
# Make the script executable
chmod +x image-converter.sh

# Run it - all setup happens automatically
./image-converter.sh
```

On first run, the script will:
1. Install missing tools (qemu-img, gzip) if needed
2. Read metadata from Step 2 (download-report.json)
3. Decompress the .img.gz file to raw format
4. Convert raw format to VHD format
5. Verify the VHD image
6. Generate conversion-report.json

## Usage

### Basic conversion (with DHCP pre-configuration)

```bash
./image-converter.sh
```

The script will:
- Find the downloaded image from Step 2
- Decompress it (if not already done)
- **Mount the raw image and pre-configure WAN for DHCP** (saves manual vim editing later)
- Convert to VHD format (if not already done)
- Skip re-processing if outputs already exist

**Benefit**: On first VM boot, the system will automatically request an IP via DHCP instead of requiring manual network configuration.

### Skip network pre-configuration

```bash
./image-converter.sh --skip-network-config
```

Converts the image without pre-configuring the network. Use this if you want to manually configure networking in the VM or are using the image for a different purpose.

### Force re-conversion

```bash
./image-converter.sh --force
```

Ignores existing files and re-processes everything, including network configuration.

### Combine options

```bash
./image-converter.sh --force --skip-network-config
```

## Network Pre-Configuration

By default, the script pre-configures OpenWrt's WAN interface for DHCP before converting to VHD. This means:

**Before** (without pre-configuration):
1. VM boots with no WAN connectivity
2. SSH into VM (or use console)
3. Manually edit `/etc/config/network` with vim
4. Set WAN interface to DHCP
5. Restart network service

**After** (with pre-configuration):
1. VM boots and automatically gets IP via DHCP
2. Ready to use immediately

The pre-configuration step:
- Mounts the raw image using loop device and kpartx (partition mapper)
- Automatically selects the root filesystem partition (typically p2 on EFI images)
- Checks if WAN is already DHCP configured (skips if already set)
- Creates or updates `/etc/config/network` with DHCP configuration for WAN and WANv6
- Safely unmounts the image (automatic cleanup even if interrupted)
- Proceeds to VHD conversion

The network configuration created:
```
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
```

To skip this step, use `--skip-network-config`.

**Note**: Network pre-configuration requires `multipath-tools` (for kpartx) which is auto-installed on Ubuntu/Debian if needed.

## Output Files

### Directory Structure

```
openwrt-vhd-converter/
├── work/
│   └── openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img
│       └── (decompressed raw image)
├── output/
│   └── openwrt-25.12.4-x86-64-generic-ext4-combined-efi.vhd
│       └── (final VirtualBox-compatible VHD)
└── conversion-report.json
    └── (metadata and paths for next step)
```

### conversion-report.json

Contains all necessary information for the next step (VM creation):

```json
{
  "version": "25.12.4",
  "source_file": "openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img.gz",
  "source_path": "/path/to/downloaded/file.img.gz",
  "source_checksum": "4fe26f6fe313c766...",
  "decompressed_file": "openwrt-25.12.4-x86-64-generic-ext4-combined-efi.img",
  "decompressed_path": "/path/to/work/file.img",
  "output_file": "openwrt-25.12.4-x86-64-generic-ext4-combined-efi.vhd",
  "output_path": "/path/to/output/file.vhd",
  "output_format": "vpc (VirtualBox VHD)",
  "file_size_mb": 520.5,
  "virtual_size": "1.5 GiB",
  "status": "converted",
  "report_generated": "2026-05-22T18:10:30Z"
}
```

## Troubleshooting

**"qemu-img required"**
- The script will attempt automatic installation on Ubuntu/Debian systems
- If automatic install fails, ensure you have `sudo` access
- Manual install: `sudo apt update && sudo apt install -y qemu-utils`

**"kpartx required" or network pre-configuration warnings**
- The script needs `kpartx` (multipath-tools) to mount partitioned images
- Automatic install will be attempted on Ubuntu/Debian
- Manual install: `sudo apt update && sudo apt install -y multipath-tools`
- If network pre-configuration fails, you can still use the VM and configure manually:
  - Boot the VM and SSH in
  - Edit `/etc/config/network` with vim
  - Set interface proto to 'dhcp'
  - Use `--skip-network-config` if you prefer manual configuration

**"Download report not found"**
- Run Step 2 first: `cd ../openwrt-release-downloader && ./release-downloader.sh`
- Then try the converter again

**"Failed to decompress image" or "Failed to convert image"**
- Check that you have sufficient disk space (requires ~2-3x the compressed image size)
- Ensure the download-report.json file is valid
- Try with `--force` to re-process: `./image-converter.sh --force`

**Insufficient disk space errors**
- Compressed image: ~13MB
- Decompressed raw image: ~500MB
- VHD output: ~520MB
- **Total needed: ~1GB free disk space**

## Error Handling

The script checks for:
- ✓ qemu-img available (auto-installs on Ubuntu/Debian)
- ✓ gzip installed (auto-installs on Ubuntu/Debian)
- ✓ kpartx available (auto-installs on Ubuntu/Debian)
- ✓ Download report exists from Step 2
- ✓ Downloaded file is accessible
- ✓ Sufficient disk space for decompression and conversion
- ✓ Proper mount/unmount of raw image during network pre-configuration (with cleanup on exit)
- ✓ VHD image is valid and usable
- ✓ File integrity and proper formatting

If any check fails, the script exits with an error message and does not leave partial files. If network configuration fails, it logs a warning but continues with VHD conversion (non-fatal error).

**Mount cleanup**: If the script is interrupted while the raw image is mounted, the EXIT trap will automatically unmount it and clean up loop devices.

## Example Pipeline

### Simple pipeline

```bash
#!/bin/bash
set -e

# Step 1: Fetch metadata (runs automatically if needed)
cd ../openwrt-release-downloader

# Step 2: Download image
echo "Downloading image..."
./release-downloader.sh

# Step 3: Convert to VHD
echo "Converting to VHD..."
cd ../openwrt-vhd-converter
./image-converter.sh

# Step 4: Use the VHD file
echo "VHD ready for VirtualBox!"
CONVERSION_REPORT=$(cat conversion-report.json)
VHD_PATH=$(echo "$CONVERSION_REPORT" | jq -r '.output_path')
echo "VHD location: $VHD_PATH"
```

### Full end-to-end pipeline

```bash
#!/bin/bash
set -e

# Setup and download
cd openwrt-release-downloader
./release-downloader.sh
DOWNLOAD_REPORT=$(cat download-report.json)

# Convert to VHD
cd ../openwrt-vhd-converter
./image-converter.sh
CONVERSION_REPORT=$(cat conversion-report.json)

# Extract information for next step
VHD_PATH=$(echo "$CONVERSION_REPORT" | jq -r '.output_path')
VHD_SIZE=$(echo "$CONVERSION_REPORT" | jq -r '.file_size_mb')
VERSION=$(echo "$CONVERSION_REPORT" | jq -r '.version')

echo "OpenWrt $VERSION ready as VHD"
echo "Size: ${VHD_SIZE}MB"
echo "Path: $VHD_PATH"

# Next: Create VM from VHD
next-step-vm-creator.sh "$VHD_PATH"
```

## Technical Details

### Conversion Process

1. **Decompression**: gzip decompresses .img.gz → raw .img
2. **Format Detection**: Identifies raw format automatically
3. **VHD Conversion**: qemu-img converts raw → vpc (VHD format)
4. **Verification**: Validates VHD using qemu-img info command
5. **Report Generation**: Creates JSON with all paths and metadata

### Format Information

- **Input**: raw disk image (.img)
- **Output**: VHD format (.vhd) — Virtual Hard Disk
- **Compatibility**: 
  - Microsoft Hyper-V (Windows/Azure)
  - Oracle VirtualBox (cross-platform)
  - Other VHD-compatible hypervisors
- **Virtual Size**: 120 MiB
- **Compressed Size**: ~37 MB on disk

### Disk Space Requirements

- Compressed (.img.gz): ~13 MB
- Decompressed (.img): ~500 MB
- VHD output (.vhd): ~520 MB (typically same size as raw image)

## Performance

Typical conversion times on modern hardware:
- Decompression: 5-10 seconds
- VHD conversion: 10-30 seconds
- Total: 15-40 seconds

## Caching Behavior

- **Decompressed files**: Cached in `work/` directory
- **VHD files**: Cached in `output/` directory
- **Smart caching**: Only re-processes if `--force` flag is used
- **Benefit**: Fast re-runs when converting multiple images

## Support for Different Architectures

Currently optimized for:
- ✓ x86_64 generic extended4 EFI images
- ✓ Other x86 images (compatible format)

Future support:
- [ ] ARM architectures (different format handling)
- [ ] MIPS architectures (different format handling)
