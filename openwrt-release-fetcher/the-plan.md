
# Mission plan: fetch OpenWrt generic-ext4-combined-efi.img.gz URL

Objective
- Visit https://downloads.openwrt.org/ and determine the current stable OpenWrt release.
- Navigate to the release's x86_64 build and obtain the full URL for `generic-ext4-combined-efi.img.gz`.
- Automate the above with a Node.js script and cache results to avoid spamming the OpenWrt site.
- Output JSON with all available download options for downstream pipeline steps.

Prerequisites
- Node.js and npm installed.
- axios and cheerio packages (lightweight HTTP client and HTML parser).

High-level steps
1. Inspect site layout
	- Manually browse https://downloads.openwrt.org/ to confirm how releases and targets are organized.
	- Identify how the stable release is indicated (e.g., top-level directory names like `22.03.5` or `23.05.1`).
2. Determine current stable release programmatically
	- Use HTTP GET on the index page and parse HTML to identify the current stable release directory.
3. Locate x86_64 build (target)
	- For the chosen release, navigate to the path where x86/64 builds live (`releases/<version>/targets/x86/64/`).
4. Extract all image files from x86_64 directory
   - Parse the x86_64 build directory and collect all `.img.gz` files with checksums and metadata.
   - Build a JSON structure with download options so downstream steps can choose which variant to use.
5. Automate with Node.js + HTTP scraping
   - Add script `fetch-openwrt.js` that uses axios + cheerio to discover all x86_64 downloads.
   - Output results as JSON to `openwrt-downloads.json`.
   - Implement caching to avoid redundant fetches (default 30 min TTL).
6. Caching & Performance
   - Check if cached JSON is fresh before fetching (saves bandwidth and API calls).
   - Provide `--force` flag to bypass cache when needed.
   - Provide `--cache-time N` to customize cache validity (in minutes).
7. Output modes for pipeline integration
   - Interactive mode: show progress and list all options.
   - Quiet mode (`-q`): silent operation, only write JSON file.
   - JSON stdout mode (`-j`): output JSON to stdout for piping to jq/downstream tools.
8. Documentation
   - Add `README.md` with installation, usage, examples, and troubleshooting.
   - Document all command-line options and pipeline integration patterns.

Deliverables
- `openwrt-release-fetcher/fetch-openwrt.js` — Node.js script to discover all x86_64 downloads with caching.
- `openwrt-release-fetcher/openwrt-downloads.json` — Output JSON file containing all available image URLs and checksums.
- `openwrt-release-fetcher/README.md` — Complete usage documentation with examples.
- `openwrt-release-fetcher/package.json` — Minimal dependencies (axios, cheerio only).

Implementation Notes
- Uses HTTP + HTML parsing (cheerio) instead of Playwright for lightweight, fast operation.
- Cache file is checked on every run; fresh data (< 30 min old) is reused automatically.
- All output modes (interactive, quiet, JSON-only) support caching.
- The script is ideal for step 1 in multi-step pipelines that need to choose from multiple image variants.
- No API key or authentication required; respects OpenWrt CDN with proper User-Agent headers.

