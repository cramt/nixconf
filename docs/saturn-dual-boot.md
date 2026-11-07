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

### 1. Boot the new config

Safe before any data moves: `/`, `/nix` and `/home` now mount via
`disk-ssd_a-pool`, which is already a member of the two-device filesystem, and
the systemd initrd waits for every btrfs member before mounting. The new
config drops the `/llm/*` mounts and colibri, which frees both LLM partitions.
Boot it rather than switch, so you see it come up off the 980's label before
anything is destroyed:

```sh
nh os boot /path/to/nixconf && systemctl reboot
```

Check `/etc/fstab` says `disk-ssd_a-pool` before going on.

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

### 1. Get the stock ISO into the store

defenestrate builds from Microsoft's stock ISO, which can't be fetched
automatically (download links expire after 24 hours). luna's store keeps a
copy, so pull that and give it a GC root so the next garbage collection
doesn't delete it:

```sh
cd /path/to/nixconf
iso=$(nix eval --raw .#windows.saturn.source.outPath)
nix copy --from ssh-ng://luna --no-check-sigs "$iso"
nix-store --add-root ./windows-iso.gcroot -r "$iso"
```

If luna doesn't have it either, download the exact ISO `nix build` asks for
from <https://www.microsoft.com/software-download/windows11> and add it with
`nix-store --add-fixed sha256 <file>` in place of the copy.

### 2. Flash Windows onto the 970

No USB stick and no installer on the real disk. defenestrate's `build.image`
runs setup in a VM inside the nix sandbox (it needs the `kvm` system
feature, which saturn has) against a 64G scratch disk, stops at setup's
first reboot, and outputs that disk as a compressed image. `build.install`
flashes it, like `flash-venus` flashes an SD card:

```sh
nix run .#windows.saturn.build.install
```

The target is `installTarget` in `hosts/saturn/windows.nix`, the 970 by-id.
It builds and checks as you and only asks for sudo to write the disk. It
refuses anything not addressed by-id, a partition, and any disk with a
mounted filesystem or a member of a mounted btrfs, and asks you to type
`ERASE`. Then it discards the 970, writes the image (~64G), moves the backup
GPT to the disk's end, grows C: over the rest in place (the partition GUID
the boot entry uses stays the same) with `ntfsresize`, and adds a firmware
entry for the 970's ESP without touching the boot order.

The image build takes ~5 minutes and ~55G of space: the 64G sparse scratch
disk fills ~29G under `/nix/var/nix/b`, and the compressed image is ~23G in
the store. The VM only ever sees the scratch disk, so setup can't
put boot files on the 980's ESP or pick the wrong disk.

Unplug the network cable, then `reboot-to-windows`. Online, OOBE's update
check can fail and wait for a click; offline it runs through: specialize,
OOBE and the shell switch, about 6 minutes to the defenestrate shell when
tested on a disk-sized file. Windows runs a chkdsk on the first boot,
because `ntfsresize` marks the volume for one.

### 3. Fallback: a USB stick

If the VM route misbehaves, the plain ISO (`.#windows.saturn.build.iso`)
installs from a stick. It isn't hybrid, so `dd` won't work; copy its files
onto FAT32 (its install image is split under 4 GiB), boot it from the
firmware menu, and pick the ~931G unallocated 970 in setup's disk picker.
With the 980 visible, setup may put its boot files on Linux's ESP: if
`ls /boot/EFI` shows `Microsoft` afterwards, shrink C: on the 970, give it an
ESP and run `bcdboot C:\Windows /s S: /f UEFI` from Windows, then delete
`/boot/EFI/Microsoft`.

### 4. Booting Windows

systemd-boot only loads from its own ESP, so Windows has no entry in its menu.
Run `reboot-to-windows`: it sets the firmware's one-shot BootNext to Windows
Boot Manager and reboots. The firmware boot menu also works.

Windows keeps the hardware clock in UTC like Linux, and Fast Startup is off, so
the 970's NTFS mounts read-write from Linux.
