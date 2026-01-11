#!/usr/bin/env node

/**
 * Declaradroid - Declarative Android app management for Waydroid
 *
 * A CLI tool that enables declarative configuration of Waydroid,
 * including app installation, ARM emulation, and system extras.
 */

import { execSync, spawn } from "child_process";
import { existsSync, readFileSync, writeFileSync, mkdirSync, unlinkSync } from "fs";
import { dirname } from "path";

const WAYDROID_CFG = "/var/lib/waydroid/waydroid.cfg";
const WAYDROID_PROP = "/var/lib/waydroid/waydroid_base.prop";
const INSTALLED_APPS_FILE = "/var/lib/waydroid/.declaradroid-apps";
const INSTALLED_EXTRAS_FILE = "/var/lib/waydroid/.declaradroid-extras";
const APK_CACHE_DIR = "/var/cache/declaradroid";

// Utility functions
function log(msg) {
  console.log(`[declaradroid] ${msg}`);
}

function error(msg) {
  console.error(`[declaradroid] ERROR: ${msg}`);
}

function run(cmd, opts = {}) {
  const { silent = false, ignoreError = false } = opts;
  try {
    const result = execSync(cmd, {
      encoding: "utf-8",
      stdio: silent ? "pipe" : "inherit",
    });
    return { success: true, output: result || "" };
  } catch (e) {
    if (!ignoreError) {
      error(`Command failed: ${cmd}`);
      if (e.stderr) error(e.stderr);
    }
    return { success: false, output: e.stdout || "", error: e.message };
  }
}

function fileExists(path) {
  return existsSync(path);
}

function readLines(path) {
  if (!fileExists(path)) return [];
  return readFileSync(path, "utf-8")
    .split("\n")
    .filter((l) => l.trim());
}

function writeLines(path, lines) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, lines.join("\n") + (lines.length > 0 ? "\n" : ""));
}

function appendLine(path, line) {
  const lines = readLines(path);
  if (!lines.includes(line)) {
    lines.push(line);
    writeLines(path, lines);
  }
}

function removeLine(path, line) {
  const lines = readLines(path).filter((l) => l !== line);
  writeLines(path, lines);
}

// Waydroid status checks
function isWaydroidInitialized() {
  return fileExists(WAYDROID_CFG);
}

function isSessionRunning() {
  const { output } = run("waydroid status 2>&1", { silent: true, ignoreError: true });
  // Session must be RUNNING and container must be RUNNING (not FROZEN)
  return output.includes("Session:\tRUNNING") && output.includes("Container:\tRUNNING");
}

function isContainerRunning() {
  const { output } = run("waydroid status 2>&1", { silent: true, ignoreError: true });
  // Check if container is at least running (even if session shows stopped when running as root)
  return output.includes("Container:\tRUNNING") || output.includes("Container:\tFROZEN");
}

function unfreezeContainer() {
  // If container is frozen, try to unfreeze it
  const { output } = run("waydroid status 2>&1", { silent: true, ignoreError: true });
  if (output.includes("Container:\tFROZEN")) {
    log("Unfreezing container...");
    // Launch show-full-ui in background to unfreeze, then wait
    run("waydroid show-full-ui &", { silent: true, ignoreError: true });
    run("sleep 3", { silent: true });
    
    // Verify unfrozen
    const { output: newStatus } = run("waydroid status 2>&1", { silent: true, ignoreError: true });
    if (newStatus.includes("Container:\tRUNNING")) {
      log("Container unfrozen");
      return true;
    }
  }
  return !output.includes("Container:\tFROZEN");
}

function ensureSessionRunning() {
  // First check if container is running at all
  if (isContainerRunning()) {
    // Always try to unfreeze - this is critical for installs to work
    unfreezeContainer();
    log("Container is running, proceeding...");
    return true;
  }

  log("Waydroid session not running.");
  log("Please start waydroid first: waydroid session start");
  log("Then re-run declaradroid.");
  return false;
}

function getInstalledPackages() {
  const { output } = run("waydroid app list 2>&1", { silent: true, ignoreError: true });
  const packages = [];
  const regex = /packageName:\s*(\S+)/g;
  let match;
  while ((match = regex.exec(output)) !== null) {
    packages.push(match[1]);
  }
  return packages;
}

function isPackageInstalled(packageId) {
  return getInstalledPackages().includes(packageId);
}

function hasArmEmulation() {
  if (!fileExists(WAYDROID_PROP)) return false;
  const content = readFileSync(WAYDROID_PROP, "utf-8");
  return /ro\.product\.cpu\.abilist=.*arm/.test(content);
}

// Actions
async function init(config) {
  if (isWaydroidInitialized()) {
    log("Waydroid already initialized");
    return true;
  }

  const imageType = config.gapps ? "GAPPS" : "VANILLA";
  log(`Initializing Waydroid with ${imageType} image...`);
  const { success } = run(`waydroid init -s ${imageType}`);
  return success;
}

function getInstalledArmEmulation() {
  if (!fileExists(WAYDROID_PROP)) return null;
  const content = readFileSync(WAYDROID_PROP, "utf-8");
  if (/ro\.product\.cpu\.abilist=.*arm/.test(content)) {
    // Check which one is installed by looking for specific markers
    // libhoudini uses different paths than libndk
    const { output } = run("ls /var/lib/waydroid/overlay/system/lib64/libhoudini.so 2>/dev/null", { silent: true, ignoreError: true });
    if (output.trim()) return "libhoudini";
    return "libndk"; // Default assumption if ARM is enabled
  }
  return null;
}

async function installArmEmulation(config) {
  if (!config.armEmulation) return true;

  if (!isWaydroidInitialized()) {
    error("Waydroid not initialized. Run 'declaradroid apply' after initializing.");
    return false;
  }

  const desired = config.armEmulation; // "libndk" or "libhoudini"
  const current = getInstalledArmEmulation();

  if (current === desired) {
    log(`ARM emulation (${desired}) already installed`);
    return true;
  }

  if (!ensureSessionRunning()) {
    log("Cannot install ARM emulation without a running Waydroid session.");
    return false;
  }

  // If switching from one to another, remove the old one first
  if (current && current !== desired) {
    log(`Removing ${current} to switch to ${desired}...`);
    run(`waydroid-script remove ${current}`, { ignoreError: true });
  }

  log(`Installing ARM emulation (${desired})...`);
  const { success } = run(`waydroid-script install ${desired}`);
  return success;
}

async function installExtras(config) {
  const extras = config.extras || {};
  const toInstall = Object.entries(extras)
    .filter(([_, enabled]) => enabled)
    .map(([name]) => name);

  if (toInstall.length === 0) return true;

  if (!isWaydroidInitialized()) {
    error("Waydroid not initialized.");
    return false;
  }

  const installed = readLines(INSTALLED_EXTRAS_FILE);
  const notInstalled = toInstall.filter((e) => !installed.includes(e));
  
  // Only need session if there's something to install
  if (notInstalled.length > 0 && !ensureSessionRunning()) {
    log("Cannot install extras without a running Waydroid session.");
    return false;
  }

  let allSuccess = true;
  for (const extra of toInstall) {
    if (installed.includes(extra)) {
      log(`${extra} already installed`);
      continue;
    }
    log(`Installing ${extra}...`);
    const { success } = run(`waydroid-script install ${extra}`, { ignoreError: true });
    if (success) {
      appendLine(INSTALLED_EXTRAS_FILE, extra);
    } else {
      allSuccess = false;
    }
  }
  return allSuccess;
}

async function setProperties(config) {
  const props = config.properties || {};
  if (Object.keys(props).length === 0) return true;

  if (!isWaydroidInitialized()) {
    error("Waydroid not initialized.");
    return false;
  }

  let allSuccess = true;
  for (const [key, value] of Object.entries(props)) {
    const propName = key.startsWith("persist.waydroid.") ? key : `persist.waydroid.${key}`;
    let propValue;
    if (typeof value === "boolean") {
      propValue = value ? "true" : "false";
    } else if (Array.isArray(value)) {
      propValue = value.join(",");
    } else {
      propValue = String(value);
    }

    log(`Setting ${propName}=${propValue}`);
    const { success } = run(`waydroid prop set ${propName} "${propValue}"`, { ignoreError: true });
    if (!success) allSuccess = false;
  }
  return allSuccess;
}

async function installApps(config) {
  const fdroidApps = config.apps?.fdroid || [];
  const apkpureApps = config.apps?.apkpure || [];

  if (fdroidApps.length === 0 && apkpureApps.length === 0) return true;

  if (!isWaydroidInitialized()) {
    error("Waydroid not initialized.");
    return false;
  }

  if (!ensureSessionRunning()) {
    log("Cannot install apps without a running Waydroid session.");
    return false;
  }

  const installed = readLines(INSTALLED_APPS_FILE);
  let allSuccess = true;

  // Install F-Droid apps
  if (fdroidApps.length > 0) {
    mkdirSync(`${APK_CACHE_DIR}/fdroid`, { recursive: true });

    log("Updating F-Droid repository index...");
    run("fdroidcl update", { ignoreError: true });

    for (const appId of fdroidApps) {
      const marker = `fdroid:${appId}`;
      
      // Check if actually installed in Waydroid (not just marker file)
      if (isPackageInstalled(appId)) {
        // Ensure marker file is in sync
        if (!installed.includes(marker)) {
          appendLine(INSTALLED_APPS_FILE, marker);
        }
        log(`${appId} already installed`);
        continue;
      }

      log(`Downloading ${appId} from F-Droid...`);
      const { success: dlSuccess } = run(
        `fdroidcl download ${appId} -o ${APK_CACHE_DIR}/fdroid/`,
        { ignoreError: true }
      );

      if (dlSuccess) {
        const { output } = run(`ls -t ${APK_CACHE_DIR}/fdroid/${appId}*.apk 2>/dev/null | head -n1`, {
          silent: true,
          ignoreError: true,
        });
        const apkFile = output.trim();

        if (apkFile) {
          log(`Installing ${appId}...`);
          run(`waydroid app install "${apkFile}"`, { ignoreError: true });
          
          // Verify installation succeeded
          if (isPackageInstalled(appId)) {
            log(`${appId} installed successfully`);
            appendLine(INSTALLED_APPS_FILE, marker);
          } else {
            error(`Failed to install ${appId} - package not found after install`);
            allSuccess = false;
          }
        } else {
          error(`Failed to find downloaded APK for ${appId}`);
          allSuccess = false;
        }
      } else {
        error(`Failed to download ${appId}`);
        allSuccess = false;
      }
    }
  }

  // Install APKPure apps
  if (apkpureApps.length > 0) {
    mkdirSync(`${APK_CACHE_DIR}/apkpure`, { recursive: true });

    for (const appId of apkpureApps) {
      const marker = `apkpure:${appId}`;
      
      // Check if actually installed in Waydroid (not just marker file)
      if (isPackageInstalled(appId)) {
        // Ensure marker file is in sync
        if (!installed.includes(marker)) {
          appendLine(INSTALLED_APPS_FILE, marker);
        }
        log(`${appId} already installed`);
        continue;
      }

      log(`Downloading ${appId} from APKPure...`);
      const { success: dlSuccess } = run(`apkeep -a ${appId} -d apk-pure ${APK_CACHE_DIR}/apkpure/`, {
        ignoreError: true,
      });

      if (dlSuccess) {
        // Check for .apk first, then .xapk
        let { output } = run(`ls -t ${APK_CACHE_DIR}/apkpure/${appId}*.apk 2>/dev/null | head -n1`, {
          silent: true,
          ignoreError: true,
        });
        let apkFile = output.trim();
        let isXapk = false;

        if (!apkFile) {
          // Check for xapk (split APK bundle)
          const { output: xapkOutput } = run(`ls -t ${APK_CACHE_DIR}/apkpure/${appId}*.xapk 2>/dev/null | head -n1`, {
            silent: true,
            ignoreError: true,
          });
          apkFile = xapkOutput.trim();
          isXapk = !!apkFile;
        }

        if (apkFile) {
          if (isXapk) {
            // Extract xapk and install split APKs using adb
            log(`Extracting split APKs from ${appId}.xapk...`);
            const extractDir = `${APK_CACHE_DIR}/apkpure/${appId}_extracted`;
            run(`rm -rf "${extractDir}"`, { silent: true, ignoreError: true });
            mkdirSync(extractDir, { recursive: true });
            
            const { success: unzipSuccess } = run(`unzip -o "${apkFile}" -d "${extractDir}"`, { ignoreError: true });
            
            if (unzipSuccess) {
              // Find all APK files in extracted directory
              const { output: apkList } = run(`ls ${extractDir}/*.apk 2>/dev/null`, {
                silent: true,
                ignoreError: true,
              });
              const apks = apkList.trim().split('\n').filter(f => f.endsWith('.apk'));
              
              if (apks.length > 0) {
                log(`Installing ${appId} (${apks.length} split APKs via adb)...`);
                
                // Use waydroid's adb connect which handles authentication
                run(`waydroid adb connect`, { ignoreError: true });
                run(`sleep 2`, { silent: true });
                
                // Install using adb install-multiple
                const apkArgs = apks.map(f => `"${f}"`).join(' ');
                const { success: installSuccess } = run(
                  `adb install-multiple -r ${apkArgs}`,
                  { ignoreError: true }
                );
                
                // Disconnect adb
                run(`waydroid adb disconnect`, { silent: true, ignoreError: true });
                
                if (!installSuccess) {
                  // Fallback: try installing base APK only via waydroid
                  log(`ADB split install failed, trying base APK only...`);
                  const baseApk = apks.find(f => f.includes(appId) && !f.includes('config.'));
                  if (baseApk) {
                    run(`waydroid app install "${baseApk}"`, { ignoreError: true });
                  }
                }
              }
            } else {
              error(`Failed to extract ${appId}.xapk`);
              allSuccess = false;
              continue;
            }
          } else {
            log(`Installing ${appId}...`);
            const { success: singleInstallSuccess, output: installOutput, error: installError } = run(`waydroid app install "${apkFile}" 2>&1`, { silent: true, ignoreError: true });
            if (!singleInstallSuccess) {
              log(`Install output: ${installOutput || installError || 'no output'}`);
            }
          }
          
          // Verify installation succeeded
          if (isPackageInstalled(appId)) {
            log(`${appId} installed successfully`);
            appendLine(INSTALLED_APPS_FILE, marker);
          } else {
            error(`Failed to install ${appId} - package not found after install`);
            allSuccess = false;
          }
        } else {
          error(`Failed to find downloaded APK for ${appId}`);
          allSuccess = false;
        }
      } else {
        error(`Failed to download ${appId}`);
        allSuccess = false;
      }
    }
  }

  return allSuccess;
}

async function cleanupApps(config) {
  const fdroidApps = config.apps?.fdroid || [];
  const apkpureApps = config.apps?.apkpure || [];

  const desired = [
    ...fdroidApps.map((id) => `fdroid:${id}`),
    ...apkpureApps.map((id) => `apkpure:${id}`),
  ];

  const installed = readLines(INSTALLED_APPS_FILE);
  const toRemove = installed.filter((marker) => !desired.includes(marker));
  
  if (toRemove.length === 0) return true;

  if (!ensureSessionRunning()) {
    log("Cannot cleanup apps without a running Waydroid session.");
    return false;
  }

  let allSuccess = true;

  for (const marker of toRemove) {
    const [source, packageId] = marker.split(":");
    log(`Uninstalling ${packageId} (removed from configuration)...`);
    run(`waydroid app uninstall "${packageId}"`, { ignoreError: true });
    removeLine(INSTALLED_APPS_FILE, marker);

    // Clean up cached APK
    run(`rm -f ${APK_CACHE_DIR}/${source}/${packageId}*.apk 2>/dev/null`, {
      silent: true,
      ignoreError: true,
    });
  }

  return allSuccess;
}

async function apply(configPath) {
  if (!fileExists(configPath)) {
    error(`Config file not found: ${configPath}`);
    process.exit(1);
  }

  let config;
  try {
    config = JSON.parse(readFileSync(configPath, "utf-8"));
  } catch (e) {
    error(`Failed to parse config file: ${e.message}`);
    process.exit(1);
  }

  log("Applying Waydroid configuration...");
  log("");

  const results = {
    init: await init(config),
    properties: await setProperties(config),
    cleanup: await cleanupApps(config),
    apps: await installApps(config),
    arm: await installArmEmulation(config),
    extras: await installExtras(config),
  };

  log("");
  log("Summary:");
  log(`  Init:       ${results.init ? "OK" : "SKIPPED/FAILED"}`);
  log(`  Properties: ${results.properties ? "OK" : "SKIPPED/FAILED"}`);
  log(`  Cleanup:    ${results.cleanup ? "OK" : "SKIPPED/FAILED"}`);
  log(`  Apps:       ${results.apps ? "OK" : "SKIPPED/FAILED"}`);
  log(`  ARM:        ${results.arm ? "OK" : "SKIPPED/FAILED"}`);
  log(`  Extras:     ${results.extras ? "OK" : "SKIPPED/FAILED"}`);

  const allSuccess = Object.values(results).every((r) => r);
  if (allSuccess) {
    log("");
    log("All tasks completed successfully!");
  } else {
    log("");
    log("Some tasks were skipped or failed. Check output above for details.");
  }
}

function status() {
  const initialized = isWaydroidInitialized();
  const running = isSessionRunning();
  const arm = getInstalledArmEmulation();

  console.log("Declaradroid Status");
  console.log("===================");
  console.log("");
  console.log("Waydroid:");
  console.log(`  Initialized:    ${initialized ? "Yes" : "No"}`);
  console.log(`  Session:        ${running ? "Running" : "Stopped"}`);
  console.log(`  ARM emulation:  ${arm || "Not installed"}`);
  console.log("");

  const installedApps = readLines(INSTALLED_APPS_FILE);
  console.log(`Managed apps (${installedApps.length}):`);
  if (installedApps.length === 0) {
    console.log("  (none)");
  } else {
    installedApps.forEach((app) => {
      const [source, id] = app.split(":");
      console.log(`  - ${id} (${source})`);
    });
  }
  console.log("");

  const installedExtras = readLines(INSTALLED_EXTRAS_FILE);
  console.log(`Managed extras (${installedExtras.length}):`);
  if (installedExtras.length === 0) {
    console.log("  (none)");
  } else {
    installedExtras.forEach((extra) => console.log(`  - ${extra}`));
  }
}

function printHelp() {
  console.log("Declaradroid - Declarative Android app management for Waydroid");
  console.log("");
  console.log("Usage: declaradroid <command> [options]");
  console.log("");
  console.log("Commands:");
  console.log("  apply <config.json>  Apply a Waydroid configuration");
  console.log("  status               Show current Waydroid/Declaradroid status");
  console.log("  help                 Show this help message");
  console.log("");
  console.log("Configuration file format (JSON):");
  console.log("  {");
  console.log('    "gapps": false,');
  console.log('    "armEmulation": true,');
  console.log('    "properties": {');
  console.log('      "multi_windows": true,');
  console.log('      "fake_touch": ["com.game.*"]');
  console.log("    },");
  console.log('    "extras": {');
  console.log('      "magisk": false,');
  console.log('      "widevine": false');
  console.log("    },");
  console.log('    "apps": {');
  console.log('      "fdroid": ["org.mozilla.fennec_fdroid"],');
  console.log('      "apkpure": ["com.microsoft.teams"]');
  console.log("    }");
  console.log("  }");
}

// Main CLI
const args = process.argv.slice(2);
const command = args[0];

switch (command) {
  case "apply":
    if (!args[1]) {
      error("Usage: declaradroid apply <config.json>");
      process.exit(1);
    }
    apply(args[1]);
    break;

  case "status":
    status();
    break;

  case "help":
  case "--help":
  case "-h":
    printHelp();
    break;

  default:
    if (command) {
      error(`Unknown command: ${command}`);
      console.log("");
    }
    printHelp();
    process.exit(command ? 1 : 0);
}
