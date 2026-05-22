#!/usr/bin/env node

/**
 * fetch-openwrt.js
 * 
 * Fetches all available x86_64 image downloads for the current stable OpenWrt release
 * and outputs a JSON file with metadata, URLs, and checksums.
 * 
 * Usage: node fetch-openwrt.js [options]
 * 
 * Options:
 *   -q, --quiet       Suppress console output (only write JSON file)
 *   -j, --json-only   Output JSON to stdout instead of file
 *   -f, --force       Force fetch even if cache is recent (< 30 min)
 *   --cache-time N    Set cache validity time in minutes (default: 30)
 *   -h, --help        Show this help message
 * 
 * Output: openwrt-downloads.json (or stdout if --json-only)
 */

const axios = require('axios');
const cheerio = require('cheerio');
const fs = require('fs');
const path = require('path');

const BASE_URL = 'https://downloads.openwrt.org';
const OUTPUT_FILE = path.join(__dirname, 'openwrt-downloads.json');
const DEFAULT_CACHE_TIME_MINUTES = 30;

// Parse command line arguments
const args = process.argv.slice(2);
const QUIET_MODE = args.includes('--quiet') || args.includes('-q');
const JSON_ONLY_MODE = args.includes('--json-only') || args.includes('-j');
const FORCE_FETCH = args.includes('--force') || args.includes('-f');
const SHOW_HELP = args.includes('--help') || args.includes('-h');

// Parse cache time if provided
let cacheTimeMinutes = DEFAULT_CACHE_TIME_MINUTES;
const cacheTimeIndex = args.findIndex(arg => arg === '--cache-time');
if (cacheTimeIndex !== -1 && cacheTimeIndex + 1 < args.length) {
  const parsedTime = parseInt(args[cacheTimeIndex + 1], 10);
  if (!isNaN(parsedTime) && parsedTime > 0) {
    cacheTimeMinutes = parsedTime;
  }
}

const log = (msg) => {
  if (!QUIET_MODE && !JSON_ONLY_MODE) {
    console.log(msg);
  }
};

if (SHOW_HELP) {
  console.log(`
OpenWrt Download Fetcher

Usage: node fetch-openwrt.js [options]

Options:
  -q, --quiet           Suppress console output (only write JSON file)
  -j, --json-only       Output JSON to stdout instead of file
  -f, --force           Force fetch even if cache is recent (< 30 min)
  --cache-time N        Set cache validity time in minutes (default: 30)
  -h, --help            Show this help message

Examples:
  # Interactive mode (default) - shows progress and options
  node fetch-openwrt.js
  
  # Quiet mode for pipeline step 1 - only writes JSON file
  # Uses cache if available (< 30 min old)
  node fetch-openwrt.js --quiet
  
  # Force refresh, ignore cache
  node fetch-openwrt.js --quiet --force
  
  # JSON to stdout for piping to jq or other tools
  node fetch-openwrt.js --json-only | jq '.version'
  
  # Custom cache time (60 minutes)
  node fetch-openwrt.js --quiet --cache-time 60
`);
  process.exit(0);
}

/**
 * Fetch HTML content from a given URL
 */
async function fetchHtml(url) {
  try {
    const response = await axios.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
      }
    });
    return response.data;
  } catch (error) {
    console.error(`Failed to fetch ${url}:`, error.message);
    throw error;
  }
}

/**
 * Parse the main downloads page and find the current stable release
 * Returns the release version (e.g., "25.12.4")
 */
async function findCurrentStableRelease() {
  log('Fetching main downloads page...');
  const html = await fetchHtml(BASE_URL);
  const $ = cheerio.load(html);

  // Find all links that contain /releases/ in their href
  // The first one that uses the main CDN (not archive.openwrt.org) is the stable release
  const stableLink = $('a[href^="releases/"]').first();
  if (!stableLink || !stableLink.attr('href')) {
    throw new Error('Could not find stable release link');
  }

  const href = stableLink.attr('href');
  const match = href.match(/releases\/([^/]+)\/targets/);
  if (!match || !match[1]) {
    throw new Error(`Could not extract version from href: ${href}`);
  }

  const version = match[1];
  log(`Found current stable release: OpenWrt ${version}`);
  return version;
}

/**
 * Parse the x86/64 target directory and extract all .img.gz files
 * Returns an array of {name, size, checksum, url}
 */
async function extractImageFiles(version) {
  const x86_64Url = `${BASE_URL}/releases/${version}/targets/x86/64/`;
  log(`Fetching x86_64 directory: ${x86_64Url}`);

  const html = await fetchHtml(x86_64Url);
  const $ = cheerio.load(html);

  const images = [];

  // Parse the directory listing table
  // The HTML has rows like:
  // <tr><td class="n"><a href="filename">name</a></td>
  //     <td class="sh">checksum</td>
  //     <td class="s">size</td>
  //     <td class="d">date</td></tr>

  $('table tr').each((_, row) => {
    const cells = $(row).find('td');
    if (cells.length === 0) return;

    const nameCell = $(cells[0]).find('a');
    if (!nameCell.length) return;

    const fileName = nameCell.text().trim();
    const fileHref = nameCell.attr('href');

    // Only include .img.gz files
    if (!fileName.endsWith('.img.gz')) {
      return;
    }

    const checksum = $(cells[1]).text().trim() || null;
    const size = $(cells[2]).text().trim() || null;
    const date = $(cells[3]).text().trim() || null;

    // Build the full URL
    const fileUrl = `${x86_64Url}${fileHref}`;

    images.push({
      name: fileName,
      size: size,
      checksum: checksum,
      date: date,
      url: fileUrl,
      displayName: fileHref.replace(/^openwrt-[\d.]+-x86-64-/, '')
    });
  });

  if (images.length === 0) {
    throw new Error('No .img.gz files found in x86/64 directory');
  }

  log(`Found ${images.length} image files`);
  return images;
}

/**
 * Check if cache file exists and is fresh (less than cacheTimeMinutes old)
 * Returns the cached data object if valid, null otherwise
 */
function checkCache() {
  if (FORCE_FETCH) {
    log('(--force flag used, ignoring cache)');
    return null;
  }

  if (!fs.existsSync(OUTPUT_FILE)) {
    return null;
  }

  try {
    const stats = fs.statSync(OUTPUT_FILE);
    const fileAgeMinutes = (Date.now() - stats.mtime.getTime()) / (1000 * 60);

    if (fileAgeMinutes < cacheTimeMinutes) {
      const cachedData = JSON.parse(fs.readFileSync(OUTPUT_FILE, 'utf8'));
      log(`✓ Using cached data (${Math.round(fileAgeMinutes)} min old, cache valid for ${cacheTimeMinutes} min)`);
      return cachedData;
    } else {
      log(`Cache expired (${Math.round(fileAgeMinutes)} min old, cache valid for ${cacheTimeMinutes} min). Refreshing...`);
      return null;
    }
  } catch (error) {
    log('Cache check failed, will fetch fresh data');
    return null;
  }
}

/**
 * Main function - orchestrates the fetch and output
 */
async function main() {
  try {
    log('Starting OpenWrt download discovery...\n');

    // Check cache first
    let output = checkCache();
    if (output) {
      // Cache hit - use cached data
      if (JSON_ONLY_MODE) {
        console.log(JSON.stringify(output, null, 2));
      } else if (!QUIET_MODE) {
        log('');
        log('Download options (from cache):');
        output.images.forEach((img, idx) => {
          log(`  ${idx + 1}. ${img.displayName}`);
          log(`     Size: ${img.size}`);
          log(`     SHA256: ${img.checksum}`);
          log(`     URL: ${img.url}\n`);
        });
        const targetImage = output.images.find(img => img.name.includes('generic-ext4-combined-efi'));
        if (targetImage) {
          log('📌 REQUESTED IMAGE (generic-ext4-combined-efi):');
          log(`   ${targetImage.url}`);
        }
      }
      return;
    }

    // Cache miss - fetch fresh data

    // Step 1: Find the current stable release
    const version = await findCurrentStableRelease();

    // Step 2: Extract all image files from x86_64 directory
    const images = await extractImageFiles(version);

    // Step 3: Build output object
    output = {
      timestamp: new Date().toISOString(),
      version: version,
      releaseUrl: `${BASE_URL}/releases/${version}/targets/`,
      x86_64Url: `${BASE_URL}/releases/${version}/targets/x86/64/`,
      imageCount: images.length,
      images: images
    };

    // Step 4: Output results (file or stdout)
    if (JSON_ONLY_MODE) {
      // Output JSON to stdout for piping
      console.log(JSON.stringify(output, null, 2));
    } else {
      // Write to JSON file
      fs.writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2));
      log(`\n✓ Successfully wrote ${images.length} images to ${OUTPUT_FILE}`);

      // Step 5: Print summary (only in interactive mode)
      log('\nDownload options:');
      images.forEach((img, idx) => {
        log(`  ${idx + 1}. ${img.displayName}`);
        log(`     Size: ${img.size}`);
        log(`     SHA256: ${img.checksum}`);
        log(`     URL: ${img.url}\n`);
      });

      // Highlight the requested image if present
      const targetImage = images.find(img => img.name.includes('generic-ext4-combined-efi'));
      if (targetImage) {
        log('📌 REQUESTED IMAGE (generic-ext4-combined-efi):');
        log(`   ${targetImage.url}`);
      }
    }

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

// Run the script
main();
