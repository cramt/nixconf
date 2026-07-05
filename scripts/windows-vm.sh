#!/usr/bin/env nix-shell
#!nix-shell -i bash -p qemu swtpm mtools dosfstools gptfdisk util-linux ntfs3g hivex coreutils findutils gnugrep gnused gawk
# shellcheck shell=bash
#
# ┌───────────────────────────────────────────────────────────────────────────┐
# │ SHELVED / EXPERIMENTAL — does not currently work.                          │
# │ Windows aborts very early booting the physical partition on this VM's      │
# │ synthesized disk topology: it loads ~3 GB then does a clean ACPI power-off │
# │ with NO BSOD and NO log entry (all Windows setup/device logs are from the  │
# │ build, not the VM boots), so it's undiagnosable without WinDbg kernel      │
# │ debugging over serial. Kept as a reference; NOT wired into the flake.      │
# └───────────────────────────────────────────────────────────────────────────┘
#
# windows-vm.sh — boot the PHYSICAL Windows partition (the one saturn dual-boots
# for League) inside a QEMU VM, so you can install apps / tweak Windows without
# rebooting. Changes write through to the real partition, so anything you set up
# here (1Password, etc.) is there when you next boot bare-metal.
#
# HOW: saturn's Windows lives on nvme1n1p1, but that disk also holds /home on
# nvme1n1p2 (mounted) — so we can't hand QEMU the whole disk. Instead we build a
# synthetic GPT disk with device-mapper: [GPT header] + [linear map of ONLY
# nvme1n1p1] + [GPT backup], giving partition 1 the same GUID the Windows BCD
# already points at. The guest sees a normal Windows disk; /home is never exposed.
# A small FAT "ESP" (built from the boot files captured by saturn-windows-image)
# provides bootmgfw.efi + BCD; OVMF boots it via the removable \EFI\BOOT fallback.
#
# CAVEATS:
#   • Do NOT run this while also booted into Windows bare-metal, and the host must
#     never mount nvme1n1p1 (this script refuses if it is mounted).
#   • Windows may flag itself "not activated" flipping between real/virtual
#     hardware — cosmetic; app installs work regardless (link a MS account to heal).
#   • Do NOT launch League/Vanguard from here — vgk.sys detects the hypervisor and
#     blocks the game (and it's gray-area for a kernel anti-cheat). VM = setup;
#     bare metal = play.
#
# USAGE (flake app):
#   nix run .#windows-vm                 boot the default saturn Windows partition
#   nix run .#windows-vm -- --part DEV   boot a different partition
#   options: --ram 8G  --cores 4  --part /dev/disk/by-id/...-partN
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PART="/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E-part1"
RAM="8G"
CORES="4"

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/saturn-windows"
ESP_TAR="$CACHE/esp-microsoft.tar"    # captured by saturn-windows-image (deploy)
WORK="$CACHE/vm-run"

log()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat <<'HELPTEXT'
windows-vm — boot saturn's physical Windows partition in a QEMU VM so you can
install apps / tweak Windows without rebooting. Changes write through to the real
partition (so 1Password etc. are there when you next boot bare-metal to play).

  nix run .#windows-vm                 boot the default saturn Windows partition
  nix run .#windows-vm -- --part DEV   boot a different partition
  options: --ram 8G   --cores 4   --part /dev/disk/by-id/...-partN

Do NOT run while booted into Windows bare-metal, and never launch League/Vanguard
from the VM (vgk.sys blocks the game in a hypervisor). VM = setup, metal = play.
HELPTEXT
}

while [ $# -gt 0 ]; do
  case "$1" in
    --part)  PART="$2"; shift ;;
    --ram)   RAM="$2"; shift ;;
    --cores) CORES="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
# run a tool as root by resolved path, so sudo's secure_path can't hide nix tools
asroot() { local b; b="$(command -v "$1")" || { echo "asroot: $1 not found" >&2; return 127; }; shift; $SUDO "$b" "$@"; }

# ── sanity ───────────────────────────────────────────────────────────────────
[ -f "$ESP_TAR" ] || die "no captured Windows boot files at $ESP_TAR — run the deploy first"
PART="$(readlink -f "$PART")"
[ -b "$PART" ] || die "not a block device: $PART"
if findmnt -rno TARGET --source "$PART" >/dev/null 2>&1; then
  die "$PART is mounted on the host — unmount it before booting the VM"
fi
GUID="$(lsblk -dno PARTUUID "$PART" | head -n1 | tr '[:lower:]' '[:upper:]')"
[ -n "$GUID" ] || die "cannot read the partition GUID of $PART"

mkdir -p "$WORK"

# tear down any leaked mapping from a previous crashed run (else it holds $PART
# open and clashes with the rw-mount / new mapping below)
for d in $(asroot dmsetup ls 2>/dev/null | awk '/^winvm-/{print $1}'); do
  asroot dmsetup remove "$d" 2>/dev/null || true
done
for f in "$WORK/gpt-head.img" "$WORK/gpt-tail.img"; do
  for l in $(asroot losetup -j "$f" 2>/dev/null | cut -d: -f1); do
    asroot losetup -d "$l" 2>/dev/null || true
  done
done

# Prepare the partition for a clean VM boot (rw-mount, which also strips any
# Fast-Startup hiberfile — else Windows tries to RESUME its saved kernel onto
# this VM's different hardware and crashes):
#   • clear MountedDevices  → drive letters reassign for the VM's disk topology
#   • force stornvme/storahci boot-start
#   • disable BSOD auto-reboot → a crash stays on screen with its stop code
log "preparing $PART for VM boot (hiberfile + offline registry fixes)"
hm="$(mktemp -d)"
asroot ntfs-3g -o remove_hiberfile "$PART" "$hm" 2>/dev/null \
  || { rmdir "$hm" 2>/dev/null || true; die "couldn't rw-mount $PART — ensure Windows is fully shut down on bare metal (not hibernated)"; }
sys="$hm/Windows/System32/config/SYSTEM"
if [ -f "$sys" ]; then
  asroot hivexsh -w "$sys" <<'HVX' 2>/dev/null || true
cd MountedDevices
del
commit
HVX
  asroot hivexregedit --merge --prefix 'HKEY_LOCAL_MACHINE\SYSTEM' "$sys" <<'REG' 2>/dev/null || true
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\stornvme]
"Start"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\storahci]
"Start"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\CrashControl]
"AutoReboot"=dword:00000000
REG
fi
asroot sync; asroot umount "$hm"; rmdir "$hm" 2>/dev/null || true

# ── 1. build a small bootable ESP from the captured \EFI\Microsoft tree ───────
log "building VM ESP from captured boot files"
ESP_IMG="$WORK/esp.img"
rm -f "$ESP_IMG"; truncate -s 320M "$ESP_IMG"
mkfs.vfat -F 32 -n WINESP "$ESP_IMG" >/dev/null
ex="$WORK/esp-extract"; rm -rf "$ex"; mkdir -p "$ex"
tar --warning=no-timestamp -C "$ex" -xf "$ESP_TAR"   # -> $ex/Microsoft/...
[ -f "$ex/Microsoft/Boot/bootmgfw.efi" ] || die "captured ESP has no bootmgfw.efi"
mmd   -i "$ESP_IMG" ::/EFI
mcopy -i "$ESP_IMG" -s "$ex/Microsoft" ::/EFI/Microsoft
# removable-media fallback (harmless) + a startup.nsh so the UEFI shell chainloads
# bootmgfw — this lets us present the ESP as a FIXED disk (Windows refuses to boot
# with its system partition on removable media).
mmd   -i "$ESP_IMG" ::/EFI/BOOT
mcopy -i "$ESP_IMG" "$ex/Microsoft/Boot/bootmgfw.efi" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ESP_IMG" "$ex/Microsoft/Boot/BCD"          ::/EFI/BOOT/BCD
printf 'FS0:\\EFI\\Microsoft\\Boot\\bootmgfw.efi\r\n' > "$WORK/startup.nsh"
mcopy -i "$ESP_IMG" "$WORK/startup.nsh" ::/startup.nsh

# ── 2. synthetic GPT disk over ONLY the Windows partition (device-mapper) ─────
log "wrapping $PART in a synthetic GPT (device-mapper) as GUID $GUID"
DM="winvm-$$"
HEAD_IMG="$WORK/gpt-head.img"; TAIL_IMG="$WORK/gpt-tail.img"
HEAD=2048; TAIL=33                                  # 1 MiB pre-gap + backup GPT
PSZ="$(asroot blockdev --getsz "$PART")"            # 512-byte sectors
truncate -s $((HEAD*512)) "$HEAD_IMG"
truncate -s $((TAIL*512)) "$TAIL_IMG"
HL=""; TL=""; DMMADE=0
HL="$(asroot losetup --show -f "$HEAD_IMG")"
TL="$(asroot losetup --show -f "$TAIL_IMG")"
cleanup() {
  [ "$DMMADE" = 1 ] && asroot dmsetup remove "$DM" 2>/dev/null || true
  [ -n "$HL" ] && asroot losetup -d "$HL" 2>/dev/null || true
  [ -n "$TL" ] && asroot losetup -d "$TL" 2>/dev/null || true
}
trap cleanup EXIT
printf '0 %d linear %s 0\n%d %d linear %s 0\n%d %d linear %s 0\n' \
  "$HEAD" "$HL" \
  "$HEAD" "$PSZ" "$PART" \
  "$((HEAD+PSZ))" "$TAIL" "$TL" | asroot dmsetup create "$DM"
DMMADE=1
DMDEV="/dev/mapper/$DM"
asroot sgdisk --clear \
  --new=1:${HEAD}:$((HEAD+PSZ-1)) \
  --typecode=1:0700 \
  --partition-guid=1:"$GUID" \
  --change-name=1:Windows "$DMDEV" >/dev/null
asroot partprobe "$DMDEV" 2>/dev/null || true
# let the unprivileged qemu open the mapped disk
asroot chown "$(id -u)" "$(readlink -f "$DMDEV")"

# ── 3. boot it ───────────────────────────────────────────────────────────────
qshare="$(cd "$(dirname "$(command -v qemu-system-x86_64)")/../share/qemu" && pwd)"
VARS="$WORK/OVMF_VARS.fd"
[ -f "$VARS" ] || install -m 0600 "$qshare/edk2-i386-vars.fd" "$VARS"
TPMDIR="$WORK/swtpm"; mkdir -p "$TPMDIR"
TPMSOCK="$WORK/swtpm.sock"
swtpm socket --tpmstate dir="$TPMDIR" --ctrl type=unixio,path="$TPMSOCK" \
  --tpm2 --daemon --pid file="$WORK/swtpm.pid" 2>/dev/null || true

log "starting Windows VM — close the window to shut down (changes persist to $PART)"
qemu-system-x86_64 \
  -name windows-vm,process=windows-vm \
  -machine q35,smm=on,vmport=off,accel=kvm \
  -cpu host,+hypervisor,+invtsc,l3-cache=on -smp cores="$CORES",threads=1,sockets=1 -m "$RAM" \
  -rtc base=localtime,clock=host,driftfix=slew \
  -global driver=cfi.pflash01,property=secure,value=on \
  -drive if=pflash,unit=0,format=raw,readonly=on,file="$qshare/edk2-x86_64-code.fd" \
  -drive if=pflash,unit=1,format=raw,file="$VARS" \
  -drive if=none,id=win,format=raw,file="$DMDEV" -device nvme,drive=win,serial=SATURNNVME,bootindex=1 \
  -chardev socket,id=chrtpm,path="$TPMSOCK" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
  -netdev user,id=n0 -device e1000e,netdev=n0 \
  -drive if=none,id=esp,format=raw,file="$ESP_IMG" -device nvme,drive=esp,serial=WINESP,bootindex=0 \
  -device qemu-xhci,id=xhci -device usb-tablet -device usb-kbd \
  -vga none -device qxl-vga,xres=1600,yres=900 -display gtk,gl=off \
  -no-shutdown \
  -monitor unix:"$WORK/mon.sock",server,nowait -serial none 2> "$WORK/qemu.log" || true

[ -f "$WORK/swtpm.pid" ] && kill "$(cat "$WORK/swtpm.pid")" 2>/dev/null || true
log "VM stopped — changes written through to $PART"
