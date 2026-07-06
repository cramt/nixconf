#!/usr/bin/env nix-shell
#!nix-shell -i bash -p qemu swtpm ntfs3g gptfdisk util-linux wimlib p7zip cdrkit hivex git coreutils findutils gnugrep gnused gawk socat imagemagick aria2 cabextract chntpw curl
# shellcheck shell=bash
#
# saturn-windows-image.sh — build a debloated Windows 11 image in a headless VM
# and lay it onto a physical partition, with zero boot media and zero WinPE.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT IT DOES
#   Phase BUILD (runs as your user, needs KVM):
#     1. Gets a Windows 11 ISO: --iso PATH if given, else a cached/downloaded ISO,
#        else builds one from uupdump (--uup-url; default 23H2 Pro) which pulls
#        UUP files straight from Microsoft (not IP-blocked like the official ISO).
#     2. Remasters the ISO: forces the legacy setup (winpeshl.ini -> setup.exe
#        /legacy in boot.wim) so 24H2/25H2's "ConX" setup can't drop the
#        specialize/oobeSystem passes, and embeds autounattend.xml inside boot.wim
#        (local account, OOBE skip, telemetry off, BitLocker auto-encrypt DISABLED,
#        HW checks bypassed). Rebuilt with efisys_noprompt.bin (no boot prompt).
#     3. Boots a headless raw-qemu VM (q35 + KVM + swtpm TPM2 + OVMF) with the
#        system disk presented as NVMe — inbox stornvme driver, matching saturn,
#        so no virtio and no sysprep. Windows installs unattended, runs
#        Win11Debloat -Silent -RunDefaults, then shuts down cleanly.
#     4. Captures the Windows NTFS partition (ntfsclone, used clusters only) and
#        the VM ESP's \EFI\Microsoft boot tree, and records the Windows
#        partition's GPT GUID.  Artifacts are cached, so re-runs skip the build.
#
#   Phase DEPLOY (needs root; auto-sudo'd):
#     5. ntfsclone-restores the image onto your target partition and grows it.
#     6. Sets the target partition's GPT GUID to match the one baked into the
#        transplanted BCD  ← this is what makes Windows boot on new hardware.
#     7. Offline registry surgery on the restored SYSTEM hive:
#          - deletes MountedDevices  (clean drive-letter reassignment)
#          - forces stornvme/storahci Start=0 (boot-start storage on real NVMe)
#     8. Copies \EFI\Microsoft into the shared ESP (default: /boot). systemd-boot
#        auto-detects "Windows Boot Manager"; otherwise use the firmware menu.
#
# WHY NO SYSPREP: the VM disk is presented as NVMe — identical to saturn — so the
# guest installs on the inbox stornvme driver and boots on saturn unchanged.
# Skipping generalize avoids appx-generalize hangs, a forced second OOBE on
# saturn, and the deprecated SkipUserOOBE. The offline MountedDevices/Start fix
# covers the rest. Trade-off: Windows digital license may want reactivation.
#
# ─────────────────────────────────────────────────────────────────────────────
# USAGE  (as a flake app: `nix run .#saturn-windows-image -- <args>`)
#   nix run .#saturn-windows-image -- --build-only        # build ISO+image, cache
#   nix run .#saturn-windows-image -- --deploy-only /dev/disk/by-id/nvme-...-part1
#   nix run .#saturn-windows-image -- /dev/.../...-part1   # build + deploy
#   ... --iso ~/Win11.iso ...       # use a specific ISO instead of uupdump
#   ... --dry-run ...               # build the real image, but never touch the disk
#
#   Options: --iso PATH  --uup-url URL  --esp DIR (default /boot)  --user NAME
#            --pass PASS  --disk-size 120G  --ram 6G  --cores 4  --rebuild
#            --dry-run  --yes (skip the destructive-write confirmation)
#
# The Windows partition on saturn is  ssd_b / part1  (hosts/saturn/disko.nix):
#   /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E-part1
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── defaults ─────────────────────────────────────────────────────────────────
WIN_USER="alex"
WIN_PASS="changeme"
WIN_HOST="SATURN-WIN"
LOCALE="en-US"
KEYBOARD="0409:00000409"          # US; da-DK is "0406:00000406"
DISK_SIZE="120G"                  # VM disk; must be < target partition (150G)
VM_RAM="6G"
VM_CORES="4"
ESP_DIR="/boot"
WIN_ISO=""                        # explicit --iso path (overrides everything below)
# uupdump "get download package" URL. With &autodl=2 it returns the Linux
# convert package, which we run to build the ISO from Microsoft's UUP servers
# (not IP-blocked like the official download). Default: Windows 11 23H2 Pro amd64.
UUP_URL="https://uupdump.net/get.php?id=8383094f-2b92-47a7-bb6a-6d3c13a6de38&pack=en-us&edition=core%3Bprofessional"
WIN11DEBLOAT_REF="2026.06.24"     # pin (date-based tags); bump deliberately
MODE="all"                        # all | build | deploy
ASSUME_YES="0"
DRY="0"                           # --dry-run: skip download/VM/writes, log intent
TARGET_PART=""
MONSOCK=""                        # set by run_vm_raw (QEMU monitor socket)
QEMU_PID=""

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/saturn-windows"
IMG="$CACHE/windows.ntfsimg"      # ntfsclone --save-image output
ESP_TAR="$CACHE/esp-microsoft.tar"
GUID_FILE="$CACHE/windows-part.guid"
WORK="$CACHE/vm"                  # per-build working dir (wiped by --rebuild)
ISO_CACHE="$CACHE/win-iso"        # built/downloaded ISO (survives --rebuild)

log()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }
# run: execute, or in --dry-run just print what would run
run()  { if [ "$DRY" = 1 ]; then printf '  \033[2m[dry] %s\033[0m\n' "$*"; else "$@"; fi; }
# asroot: run a tool as root by its resolved absolute path, so sudo's secure_path
# can't hide nix-store binaries (sgdisk, ntfsclone, hivexsh, …). $SUDO is "" as root.
asroot() { local b; b="$(command -v "$1")" || { echo "asroot: $1 not found" >&2; return 127; }; shift; $SUDO "$b" "$@"; }

usage() {
  cat <<'HELPTEXT'
saturn-windows-image — build a debloated Windows 11 image in a headless VM and
flash it onto a physical partition (no boot media, no WinPE).

USAGE (flake app):
  nix run .#saturn-windows-image -- --build-only         build ISO + image, cache it
  nix run .#saturn-windows-image -- --deploy-only DEVICE  flash cached image to DEVICE
  nix run .#saturn-windows-image -- DEVICE                build + deploy
  nix run .#saturn-windows-image -- --dry-run DEVICE      build image, never touch disk

  DEVICE = target Windows partition, e.g.
    /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E-part1

OPTIONS:
  --iso PATH        use a specific Windows ISO instead of building via uupdump
  --uup-url URL     uupdump get.php URL to build the ISO from (default: 23H2 Pro)
  --esp DIR         ESP mountpoint for Windows boot files (default: /boot)
  --user NAME       local account name (default: alex)
  --pass PASS       local account password (default: changeme)
  --disk-size SIZE  VM disk size; must be < target partition (default: 120G)
  --ram SIZE        VM RAM (default: 6G)      --cores N   VM vCPUs (default: 4)
  --rebuild         wipe the build cache and rebuild from scratch
  --dry-run         build the real image but never write to the target disk/ESP
  --yes, -y         skip the destructive-write confirmation prompt
HELPTEXT
}

# ── arg parsing ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --build-only)  MODE="build" ;;
    --deploy-only) MODE="deploy" ;;
    --rebuild)     rm -f "$IMG" "$ESP_TAR" "$GUID_FILE"; rm -rf "$WORK" ;;
    --esp)         ESP_DIR="$2"; shift ;;
    --iso)         WIN_ISO="$2"; shift ;;
    --uup-url)     UUP_URL="$2"; shift ;;
    --user)        WIN_USER="$2"; shift ;;
    --pass)        WIN_PASS="$2"; shift ;;
    --disk-size)   DISK_SIZE="$2"; shift ;;
    --ram)         VM_RAM="$2"; shift ;;
    --cores)       VM_CORES="$2"; shift ;;
    --yes|-y)      ASSUME_YES="1" ;;
    --dry-run)     DRY="1" ;;
    -h|--help)     usage; exit 0 ;;
    -*)            die "unknown option: $1" ;;
    *)             TARGET_PART="$1" ;;
  esac
  shift
done

[ "$MODE" != "build" ] && [ -z "$TARGET_PART" ] && die "target partition required (or use --build-only)"
mkdir -p "$CACHE"

# ── privilege helper: run the deploy bits via sudo, keep the VM as the user ───
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# ═════════════════════════════════════════════════════════════════════════════
#  PHASE: BUILD
# ═════════════════════════════════════════════════════════════════════════════
build_autounattend() {
  local stage="$1"
  cat > "$stage/autounattend.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
          xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

  <!-- ===== 1. WinPE: bypass Win11 checks, wipe disk 0, install ============ -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage><UILanguage>${LOCALE}</UILanguage></SetupUILanguage>
      <InputLocale>${KEYBOARD}</InputLocale>
      <SystemLocale>${LOCALE}</SystemLocale>
      <UILanguage>${LOCALE}</UILanguage>
      <UserLocale>${LOCALE}</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add"><Order>1</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>2</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>3</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>4</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>5</Order><Path>reg add HKLM\System\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
      </RunSynchronous>
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
          <InstallToAvailablePartition>false</InstallToAvailablePartition>
        </OSImage>
      </ImageInstall>
      <UserData>
        <ProductKey><Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key><WillShowUI>OnError</WillShowUI></ProductKey>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>

  <!-- ===== 2. specialize: BitLocker off, stage Win11Debloat off the CD ==== -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>${WIN_HOST}</ComputerName>
    </component>
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add"><Order>1</Order><Path>reg add "HKLM\SYSTEM\CurrentControlSet\Control\BitLocker" /v PreventDeviceEncryption /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add"><Order>2</Order><Path>cmd /c for %i in (D E F G H I J K) do @if exist %i:\Win11Debloat\Win11Debloat.ps1 xcopy /E /I /Y %i:\Win11Debloat C:\Win11Debloat\</Path></RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>

  <!-- ===== 3. oobeSystem: local account, autologon, debloat, shutdown ===== -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>${KEYBOARD}</InputLocale>
      <SystemLocale>${LOCALE}</SystemLocale>
      <UILanguage>${LOCALE}</UILanguage>
      <UserLocale>${LOCALE}</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>${WIN_USER}</Name>
            <DisplayName>${WIN_USER}</DisplayName>
            <Group>Administrators</Group>
            <Password><Value>${WIN_PASS}</Value><PlainText>true</PlainText></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>${WIN_USER}</Username>
        <LogonCount>1</LogonCount>
        <Password><Value>${WIN_PASS}</Value><PlainText>true</PlainText></Password>
      </AutoLogon>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>cmd /c powercfg /h off</CommandLine>
          <Description>disable hibernation/Fast Startup (clean shutdown, no hiberfile)</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>powershell -NoProfile -ExecutionPolicy Bypass -File C:\Win11Debloat\Win11Debloat.ps1 -Silent -RunDefaults</CommandLine>
          <Description>Win11Debloat</Description>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>cmd /c shutdown /s /t 8 /f</CommandLine>
          <Description>shutdown so the host can capture</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
EOF
}

# Find a Windows ISO WITHOUT building one (this runs inside $(...), so it must
# only echo the path). Order: --iso > a previously-built/cached ISO > a real
# (multi-GB) ISO in common dirs, ignoring tiny helper ISOs (unattend/virtio/spice).
resolve_win_iso() {
  local min=$((3*1024*1024*1024)) f best="" bestsz=0 sz
  if [ -n "$WIN_ISO" ]; then
    [ -f "$WIN_ISO" ] && { echo "$WIN_ISO"; return 0; } || return 1
  fi
  local cached; cached="$(find "$ISO_CACHE" -maxdepth 1 -iname '*.iso' 2>/dev/null | head -n1)"
  [ -n "$cached" ] && { echo "$cached"; return 0; }
  while IFS= read -r -d '' f; do
    case "${f,,}" in *unattend*|*virtio*|*spice*) continue ;; esac
    sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
    [ "$sz" -ge "$min" ] && [ "$sz" -gt "$bestsz" ] && { best="$f"; bestsz="$sz"; }
  done < <(find "$WORK/windows-11" "$WORK" "$HOME/Downloads" "$HOME" \
             -maxdepth 1 -iname '*.iso' -print0 2>/dev/null)
  [ -n "$best" ] && { echo "$best"; return 0; } || return 1
}

# Build a Windows ISO from a uupdump package URL (downloads UUP files from
# Microsoft, then assembles the ISO). Result lands in $ISO_CACHE. Logs to stdout,
# so call this OUTSIDE a command substitution. ~20-40 min the first time.
build_iso_from_uup() {
  mkdir -p "$ISO_CACHE"
  local d="$ISO_CACHE/uup-build"; mkdir -p "$d"
  if [ ! -f "$d/uup_download_linux.sh" ]; then
    log "fetching uupdump conversion package"
    curl -fSL "${UUP_URL}&autodl=2" -o "$d/pkg.zip"
    ( cd "$d" && 7z x -y pkg.zip >/dev/null )
  fi
  log "downloading Windows UUP files from Microsoft + assembling ISO (~20–40 min)"
  # uup_download_linux.sh fetches the UUPs, then tries ./files/convert.sh whose
  # #!/bin/bash shebang fails on NixOS — so let it download, then convert with
  # an explicit bash (convert.sh sources its ve plugin, no shebang issue).
  ( cd "$d" && bash uup_download_linux.sh ) || true
  ( cd "$d" && bash files/convert.sh wim UUPs 0 )
  local iso; iso="$(find "$d" -maxdepth 1 -iname '*.iso' 2>/dev/null | head -n1)"
  [ -n "$iso" ] || die "uupdump build produced no ISO (check network / the URL)"
  mv -f "$iso" "$ISO_CACHE/"
  log "built ISO: $ISO_CACHE/$(basename "$iso")"
}

# Windows guests need the host KVM to ignore unhandled MSRs, or they hang at boot.
ensure_ignore_msrs() {
  local v; v="$(cat /sys/module/kvm/parameters/ignore_msrs 2>/dev/null || echo N)"
  case "$v" in Y|1) return 0 ;; esac
  warn "KVM ignore_msrs is off — Windows VMs hang without it. Enabling (needs sudo)…"
  echo 1 | $SUDO tee /sys/module/kvm/parameters/ignore_msrs >/dev/null 2>&1 || \
    warn "could not set it — run: echo 1 | sudo tee /sys/module/kvm/parameters/ignore_msrs"
}

# Send one HMP command to the running VM's QEMU monitor.
mon() { printf '%s\n' "$1" | socat - unix-connect:"$MONSOCK" >/dev/null 2>&1 || true; }

# Screen-dump the headless VM to a PNG (for supervising the install).
vm_screenshot() {
  local png="$1" ppm="${1%.png}.ppm"
  mon "screendump $ppm"; sleep 1
  [ -f "$ppm" ] && magick "$ppm" "$png" 2>/dev/null
}

# Remaster the Windows ISO for a deterministic unattended install (method used by
# dockur/windows). 24H2/25H2 ship a new "ConX" setup that drops the specialize/
# oobeSystem passes; we force the legacy setup via winpeshl.ini in boot.wim, and
# embed autounattend.xml *inside* boot.wim (materializes as X:\autounattend.xml)
# so there's zero removable-media detection variance. efisys_noprompt.bin kills
# the "Press any key to boot from CD" prompt. Produces $out (a bootable ISO).
prepare_media() {
  local winiso="$1" stage="$2" out="$3"
  local ex="$WORK/iso-extract"
  rm -rf "$ex"; mkdir -p "$ex"

  log "extracting Windows ISO (7z reads its UDF)"
  7z x -y -o"$ex" "$winiso" >/dev/null
  chmod -R u+w "$ex"

  # locate the real (case-varying) boot.wim + boot images
  local wim etfs efisys
  wim="$(find "$ex" -ipath '*/sources/boot.wim' | head -n1)"
  etfs="$(cd "$ex" && find . -ipath './boot/etfsboot.com' | head -n1 | sed 's#^\./##')"
  efisys="$(cd "$ex" && find . -ipath './efi/microsoft/boot/efisys_noprompt.bin' | head -n1 | sed 's#^\./##')"
  [ -f "$wim" ] || die "boot.wim not found in extracted ISO"
  [ -n "$etfs" ] && [ -n "$efisys" ] || die "boot images (etfsboot/efisys_noprompt) not found"

  # 24H2+ (build >=26000) ships the "ConX" setup that ignores answer files, so we
  # force legacy setup via winpeshl. Older releases (23H2 = 22631) use the classic
  # setup which honors autounattend natively — no winpeshl needed (and /legacy may
  # not be a valid flag there).
  local iwim build conx=0
  iwim="$(find "$ex" \( -ipath '*/sources/install.wim' -o -ipath '*/sources/install.esd' \) | head -n1)"
  build="$(wimlib-imagex info "$iwim" 2>/dev/null | grep -iE '^Build:' | grep -oE '[0-9]+' | head -1)"
  [ -n "$build" ] && [ "$build" -ge 26000 ] && conx=1

  # boot.wim index 2 = "Windows Setup" (index 1 is bare WinPE); fall back to 1
  local idx=1
  wimlib-imagex info "$wim" 2>/dev/null | grep -qiE '^Index[[:space:]]*:[[:space:]]*2' && idx=2

  log "embedding answer file into boot.wim (index $idx; build ${build:-?}, ConX=$conx)"
  {
    echo "add $stage/autounattend.xml /autounattend.xml"
    echo "add $stage/autounattend.xml /autounattend.dat"
    if [ "$conx" = 1 ]; then
      printf '[LaunchApps]\r\n%%SYSTEMDRIVE%%\\sources\\setup.exe, /legacy /unattend:%%SYSTEMDRIVE%%\\autounattend.xml\r\n' > "$WORK/winpeshl.ini"
      echo "add $WORK/winpeshl.ini /Windows/System32/winpeshl.ini"
    fi
  } | wimlib-imagex update "$wim" "$idx" >/dev/null

  # also on the media root (legacy setup search) + Win11Debloat for the specialize copy
  cp -f "$stage/autounattend.xml" "$ex/autounattend.xml"
  rm -rf "$ex/Win11Debloat"; cp -r "$stage/Win11Debloat" "$ex/Win11Debloat"

  log "rebuilding bootable ISO ($efisys, no boot prompt)"
  rm -f "$out"
  genisoimage -o "$out" -b "$etfs" -no-emul-boot -c BOOT.CAT \
    -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V WIN_UA -udf \
    -boot-info-table -eltorito-alt-boot -eltorito-boot "$efisys" -no-emul-boot \
    -allow-limited-size -quiet "$ex"
  rm -rf "$ex"
}

# Raw qemu: q35 + KVM + swtpm(TPM2) + OVMF, disk presented as NVMe so the guest
# uses the inbox stornvme driver — identical to saturn, so no virtio and no
# sysprep needed for the transplant. Backgrounds qemu into $QEMU_PID.
run_vm_raw() {
  local installiso="$1" disk_raw="$2"
  local vmdir; vmdir="$(dirname "$disk_raw")"
  local qshare; qshare="$(cd "$(dirname "$(command -v qemu-system-x86_64)")/../share/qemu" && pwd)"
  local code="$qshare/edk2-x86_64-code.fd"
  local vars="$vmdir/OVMF_VARS.fd"
  install -m 0600 "$qshare/edk2-i386-vars.fd" "$vars"  # store copy is 0444; need writable
  qemu-img create -f raw "$disk_raw" "$DISK_SIZE" >/dev/null

  local tpmdir="$vmdir/swtpm"; mkdir -p "$tpmdir"
  local tpmsock="$vmdir/swtpm.sock"
  swtpm socket --tpmstate dir="$tpmdir" --ctrl type=unixio,path="$tpmsock" \
    --tpm2 --daemon --pid file="$vmdir/swtpm.pid" 2>/dev/null

  MONSOCK="$vmdir/monitor.sock"; rm -f "$MONSOCK"

  qemu-system-x86_64 \
    -name win11build,process=win11build \
    -machine q35,smm=on,vmport=off,accel=kvm \
    -global kvm-pit.lost_tick_policy=discard -global ICH9-LPC.disable_s3=1 \
    -cpu host,+hypervisor,+invtsc,l3-cache=on,migratable=no \
    -smp cores="$VM_CORES",threads=1,sockets=1 -m "$VM_RAM" \
    -rtc base=localtime,clock=host,driftfix=slew \
    -device virtio-balloon \
    -vga none -device qxl-vga,xres=1280,yres=800 -display none \
    -device virtio-rng-pci,rng=rng0 -object rng-random,id=rng0,filename=/dev/urandom \
    -device qemu-xhci,id=xhci -device usb-kbd -device usb-tablet \
    -netdev user,id=nic -device virtio-net-pci,netdev=nic \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,unit=0,file="$code",readonly=on \
    -drive if=pflash,format=raw,unit=1,file="$vars" \
    -drive id=install,if=none,media=cdrom,file="$installiso" \
    -device ide-cd,drive=install,bootindex=1 \
    -device nvme,drive=SystemDisk,serial=SATURNNVME,bootindex=0 \
    -drive id=SystemDisk,if=none,format=raw,file="$disk_raw",discard=unmap,detect-zeroes=unmap,cache=writeback,aio=threads \
    -chardev socket,id=chrtpm,path="$tpmsock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -monitor unix:"$MONSOCK",server,nowait -serial none &
  QEMU_PID=$!

  # efisys_noprompt.bin boots WinPE with no "press any key" prompt — nothing to nudge.
  sleep 10
  local waited=0 cap=$((3*3600))
  while kill -0 "$QEMU_PID" 2>/dev/null; do
    sleep 30; waited=$((waited+30))
    if [ "$waited" -ge "$cap" ]; then
      kill -9 "$QEMU_PID" 2>/dev/null || true
      die "VM still running after 3h — inspect $disk_raw (install may have stalled)"
    fi
  done
  [ -f "$vmdir/swtpm.pid" ] && kill "$(cat "$vmdir/swtpm.pid")" 2>/dev/null || true
  log "VM powered off after $((waited/60))m"
}

phase_build() {
  if [ -f "$IMG" ] && [ -f "$ESP_TAR" ] && [ -f "$GUID_FILE" ]; then
    log "cached image present ($IMG) — skipping build (use --rebuild to force)"
    return 0
  fi
  local disk_raw="$WORK/windows-11/disk.raw"
  local marker="$WORK/windows-11/.vm-installed"

  if [ -f "$disk_raw" ] && [ -f "$marker" ]; then
    log "VM already built — resuming at capture (skipping the install)"
  else
    [ -e /dev/kvm ] || die "/dev/kvm not available — KVM required for the build"
    [ -w /dev/kvm ] || warn "you may not be in the 'kvm' group; VM could be slow/fail"
    ensure_ignore_msrs

    local winiso
    if ! winiso="$(resolve_win_iso)"; then
      # nothing found — build one from uupdump (default 23H2 Pro)
      build_iso_from_uup
      winiso="$(resolve_win_iso)" || die "no Windows ISO and uupdump build failed"
    fi
    log "using Windows ISO: $winiso"

    mkdir -p "$WORK/windows-11"
    local stage="$WORK/unattend-cd"
    rm -rf "$stage"; mkdir -p "$stage"

    log "fetching Win11Debloat ${WIN11DEBLOAT_REF}"
    git clone --depth 1 --branch "$WIN11DEBLOAT_REF" \
      https://github.com/Raphire/Win11Debloat "$stage/Win11Debloat"
    rm -rf "$stage/Win11Debloat/.git"

    log "writing autounattend.xml"
    build_autounattend "$stage"

    log "remastering ISO (legacy setup + embedded answer file)"
    prepare_media "$winiso" "$stage" "$WORK/windows-11/install.iso"

    rm -f "$disk_raw" "$marker"
    log "booting headless VM (raw qemu, NVMe disk) — installs + debloats (~30–60 min)"
    run_vm_raw "$WORK/windows-11/install.iso" "$disk_raw"
    touch "$marker"
    log "capturing"
  fi

  capture "$disk_raw"
}

capture() {
  local disk_raw="$1" loop part_win part_esp guid n
  loop="$($SUDO losetup --show -fP "$disk_raw")"
  # shellcheck disable=SC2064
  trap "$SUDO losetup -d '$loop' 2>/dev/null || true" RETURN
  $SUDO partprobe "$loop" 2>/dev/null || true; sleep 1

  # Windows = largest ntfs partition; ESP = the vfat one. Enumerate the loop's
  # own partition nodes rather than trusting the blkid cache.
  part_win=""; part_esp=""
  for d in "${loop}"p*; do
    [ -b "$d" ] || continue
    case "$($SUDO blkid -o value -s TYPE "$d" 2>/dev/null)" in
      ntfs) part_win="$d" ;;
      vfat) part_esp="$d" ;;
    esac
  done
  [ -n "$part_win" ] || die "no NTFS partition found on the VM disk (install failed?)"
  [ -n "$part_esp" ] || die "no ESP (vfat) partition found on the VM disk"
  n="${part_win##*p}"
  guid="$(asroot sgdisk -i="$n" "$loop" | awk -F': ' '/Partition unique GUID/{print $2}')"
  [ -n "$guid" ] || die "could not read Windows partition GUID"

  log "capturing NTFS ($part_win) → $IMG"
  asroot ntfsclone --save-image --output "$IMG" "$part_win"
  $SUDO chown "$(id -u):$(id -g)" "$IMG"

  log "capturing \\EFI\\Microsoft from ESP ($part_esp)"
  local m; m="$(mktemp -d)"
  $SUDO mount -o ro "$part_esp" "$m"
  [ -d "$m/EFI/Microsoft" ] || { $SUDO umount "$m"; die "VM ESP has no EFI/Microsoft"; }
  $SUDO tar -C "$m/EFI" -cf "$ESP_TAR" Microsoft
  $SUDO chown "$(id -u):$(id -g)" "$ESP_TAR"
  $SUDO umount "$m"; rmdir "$m"

  echo "$guid" > "$GUID_FILE"
  log "capture complete — Windows partition GUID $guid"
}

# ═════════════════════════════════════════════════════════════════════════════
#  PHASE: DEPLOY
# ═════════════════════════════════════════════════════════════════════════════
phase_deploy() {
  if [ -f "$IMG" ] && [ -f "$ESP_TAR" ] && [ -f "$GUID_FILE" ]; then :;
  elif [ "$DRY" = 1 ]; then warn "no cached image (dry-run: continuing anyway)";
  else die "no cached image — run a build first"; fi
  local part="$TARGET_PART"
  [ -b "$(readlink -f "$part")" ] || die "not a block device: $part"
  part="$(readlink -f "$part")"

  local disk n
  n="$(cat "/sys/class/block/$(basename "$part")/partition" 2>/dev/null)" || \
    die "cannot determine partition number of $part"
  disk="/dev/$(lsblk -no pkname "$part" | head -n1)"
  [ -b "$disk" ] || die "cannot determine parent disk of $part"

  # refuse if mounted
  if findmnt -rno TARGET --source "$part" >/dev/null 2>&1; then
    die "$part is mounted — unmount it first"
  fi

  local guid; guid="$(cat "$GUID_FILE" 2>/dev/null || echo '<from-build>')"
  # size via sysfs (world-readable, no root needed): sectors × 512
  local tgt_bytes; tgt_bytes=$(( $(cat "/sys/class/block/$(basename "$part")/size") * 512 ))

  cat <<EOF

  ────────────────────────────────────────────────────────────
   $([ "$DRY" = 1 ] && echo "DEPLOY PREVIEW (dry-run: no writes)" || echo "DESTRUCTIVE WRITE")
     image      : $IMG
     → partition: $part   (disk $disk, part $n, $((tgt_bytes/1024/1024/1024))G)
     set GUID   : $guid
     ESP target : $ESP_DIR
  ────────────────────────────────────────────────────────────
EOF
  if [ "$ASSUME_YES" != "1" ] && [ "$DRY" != 1 ]; then
    read -r -p "  Type YES to write Windows onto $part: " ans
    [ "$ans" = "YES" ] || die "aborted"
  fi

  log "restoring NTFS image → $part"
  run asroot ntfsclone --restore-image --overwrite "$part" "$IMG"

  log "growing NTFS to fill the partition"
  if [ "$DRY" = 1 ]; then run asroot ntfsresize -f "$part";
  else asroot ntfsresize -f "$part" >/dev/null 2>&1 || \
    warn "ntfsresize skipped/failed — Windows will just see a smaller C:"; fi

  log "matching partition GPT GUID to the BCD ($guid)"
  run asroot sgdisk --partition-guid="${n}:${guid}" "$disk"
  [ "$DRY" = 1 ] || { $SUDO partprobe "$disk" 2>/dev/null || true; sleep 1; }

  log "offline registry fix (MountedDevices + boot-start storage)"
  if [ "$DRY" = 1 ]; then
    run asroot ntfs-3g -o remove_hiberfile "$part" /mnt/tmp
    run "hivexsh: del MountedDevices; hivexregedit: stornvme/storahci Start=0"
  else
    local m; m="$(mktemp -d)"
    # ntfs-3g (FUSE) rather than -t ntfs3: it mounts a just-resized/dirty NTFS
    # that the stricter in-kernel ntfs3 driver rejects. remove_hiberfile forces
    # rw even if Windows left a Fast-Startup hiberfile (else it mounts read-only
    # and the hive edits silently fail).
    asroot ntfs-3g -o remove_hiberfile "$part" "$m"
    local sys="$m/Windows/System32/config/SYSTEM"
    [ -f "$sys" ] || { $SUDO umount "$m"; die "restored volume has no SYSTEM hive"; }
    # clear stale drive-letter bindings so C: reassigns cleanly on new hardware
    asroot hivexsh -w "$sys" <<'HVX' 2>/dev/null || warn "MountedDevices clear skipped"
cd MountedDevices
del
commit
HVX
    # guarantee the inbox NVMe/AHCI drivers load at boot on real hardware
    asroot hivexregedit --merge --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' "$sys" <<'REG' || \
      warn "storage boot-start merge skipped"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\stornvme]
"Start"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\storahci]
"Start"=dword:00000000
REG
    $SUDO sync; $SUDO umount "$m"; rmdir "$m"
  fi

  log "installing Windows boot files into ESP ($ESP_DIR)"
  findmnt -rno TARGET "$ESP_DIR" >/dev/null 2>&1 || \
    warn "$ESP_DIR is not a mountpoint — make sure it is the ESP"
  run $SUDO mkdir -p "$ESP_DIR/EFI"
  run $SUDO tar --warning=no-timestamp -C "$ESP_DIR/EFI" -xf "$ESP_TAR"

  cat <<EOF

  ✅ Done. Windows is on $part and \EFI\Microsoft is on the ESP.

  Boot it:
   • systemd-boot should now list "Windows Boot Manager" automatically.
     If not, pick it from the firmware boot menu (F-key at POST).
   • First login: user "$WIN_USER", password "$WIN_PASS".
   • Windows may reactivate itself over the network (hardware changed).

EOF
}

# ═════════════════════════════════════════════════════════════════════════════
case "$MODE" in
  build)  phase_build ;;
  deploy) phase_deploy ;;
  all)    phase_build; phase_deploy ;;
esac
