# saturn: one SSD for Linux, one for Windows

saturn's two NVMe SSDs used to form one btrfs filesystem (`nvme-pool`, data
`single`, metadata `raid1`), each with an ext4 LLM partition on the end and a
150G Windows slot on the 970 EVO. The goal:

| Drive | Holds |
|-------|-------|
| Samsung 980 | `disk-ssd_a-ESP` (`/boot`) and `disk-ssd_a-pool`, the whole `nvme-pool` btrfs (`/`, `/nix`, `/home`) |
| Samsung 970 EVO | Windows, installed by [defenestrate](https://github.com/cramt/defenestrate). Windows setup owns the whole disk, ESP included. |

Chapter 1 moves Linux onto the 980 and frees the 970. Chapter 2 installs
Windows on it.

Always address the disks by-id. `nvmeXn1` numbering swaps between boots.

```sh
linux=/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL1T766468L
windows=/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS1NB05355E
```

## Chapter 1: clean up the disks

Runs in place on the live system, no reinstall or rescue media. The 980
already holds the ESP and the larger pool member (p2), and its LLM partition
(p3) is last on the disk, so p2 can grow into the space p3 leaves.

**Destroys:** the LLM weights on both drives, and the old Windows install on
the 970 EVO's p1. Copy anything you want off the Windows partition first.

### 1. Deploy the new config

Safe before any data moves: `/`, `/nix` and `/home` now mount via
`disk-ssd_a-pool`, which is already a member of the two-device filesystem, and
stage 1 scans for all btrfs members before mounting. The deploy drops the
`/llm/*` mounts and colibri, which frees both LLM partitions.

```sh
just deploy saturn
```

### 2. Grow the 980's member over its LLM partition

```sh
mountpoint -q /llm/mirror && sudo umount /llm/mirror
sudo parted "$linux" rm 3
sudo parted "$linux" resizepart 2 100%
sudo partprobe "$linux"
sudo btrfs filesystem show /      # note the devid of the 980's member
sudo btrfs filesystem resize <devid>:max /
```

### 3. Move everything off the 970 EVO

btrfs refuses to drop below two devices while metadata is `raid1`, so convert
it to `dup` first. `device remove` then moves every chunk on the 970's member
onto the 980. It runs online and takes a while.

```sh
sudo btrfs filesystem usage /     # data used has to fit on the 980 alone (~930G)
sudo btrfs balance start -f -mconvert=dup -sconvert=dup /
sudo btrfs device remove "$windows-part2" /
sudo btrfs filesystem show /      # exactly one device, the 980
```

Reboot here, to see Linux come up off the 980 alone before touching the 970.

### 4. Wipe the 970 EVO and the old Windows boot files

```sh
sudo sgdisk --zap-all "$windows"
# The old install's boot files lived on the shared ESP; the new one brings its own.
sudo rm -r /boot/EFI/Microsoft
sudo efibootmgr                   # delete any stale "Windows Boot Manager": sudo efibootmgr -b XXXX -B
```

## Chapter 2: install Windows with defenestrate

The install is declared in `hosts/saturn/windows.nix`: local account `cramt`,
Danish keyboard, Copenhagen time, and defenestrate's debloat and shell.

### 1. Build the ISO

defenestrate builds from Microsoft's stock ISO, which can't be fetched
automatically (download links expire after 24 hours). Download the exact ISO
`nix build` asks for from
<https://www.microsoft.com/software-download/windows11>, then add it to the
store with a GC root so the next garbage collection doesn't delete it:

```sh
cd /pool/dev/nixconf   # or wherever nixconf is checked out
nix-store --add-root ./windows-iso.gcroot -r \
  "$(nix-store --add-fixed sha256 ~/Downloads/Windows11_Client_x64_*.iso)"
nix build .#windows.saturn.build.iso -o saturn-windows.iso
```

The build needs ~25G of scratch space and takes a few minutes.

### 2. Put it on a USB stick

The ISO isn't hybrid, so `dd` won't make a bootable stick. Its install image is
split into parts under 4 GiB, so copying the files onto a FAT32 stick works,
and UEFI firmware boots that directly. This wipes the stick:

```sh
stick=/dev/disk/by-id/usb-...      # ls /dev/disk/by-id/usb-*, the whole disk, not -part1
sudo sgdisk --zap-all -n 1:0:0 -t 1:0700 "$stick"
sudo mkfs.vfat -F 32 -n WININSTALL "$stick-part1"
sudo mkdir -p /mnt/iso /mnt/stick
sudo mount -o loop,ro saturn-windows.iso/*.iso /mnt/iso
sudo mount "$stick-part1" /mnt/stick
sudo cp -r /mnt/iso/. /mnt/stick/
sudo umount /mnt/iso /mnt/stick
```

### 3. Install

1. Unplug the network cable. Online, OOBE's update check can fail and wait for a
   click; offline the install runs through without input.
2. Boot the stick from the firmware boot menu, and press a key at "Press any
   key to boot from CD or DVD".
3. In setup's disk picker, choose the 970 EVO: the ~931G disk with only
   unallocated space. Don't choose the 980; it holds Linux. Setup partitions
   the 970 itself, its own ESP included.
4. The rest runs unattended: specialize, OOBE, then one reboot on first logon
   to switch the shell.

Back on Linux, check that setup created its own ESP and didn't reuse the 980's:
`ls /boot/EFI` must not show `Microsoft`. If it does, move it to the 970's ESP
or reinstall with the 980 unplugged.

### 4. Booting Windows

systemd-boot only loads from its own ESP, so Windows has no entry in its menu.
Run `reboot-to-windows`: it sets the firmware's one-shot BootNext to Windows
Boot Manager and reboots. The firmware boot menu also works.

Windows keeps the hardware clock in UTC like Linux, and Fast Startup is off, so
the 970's NTFS mounts read-write from Linux.
