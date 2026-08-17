# Saturn LLM streaming tier

Dedicated NVMe partitions for [colibrì](https://github.com/JustVugg/colibri), which
runs frontier MoE models by streaming expert weights off disk instead of holding
them in RAM. Declared in `hosts/saturn/disko.nix`; consumed by
`myNixOS.services.colibri` (`modules/services/colibri.nix`).

**This does not need a reinstall.** Both LLM partitions are the *last* partition
on their drive, which is the whole point of the layout: shrinking a btrfs member
frees space at the end of a disk, so a tail partition is the one thing that can
be added in place. See [In place, no reinstall](#in-place-no-reinstall) below.
Nothing gets renumbered and no existing partition moves.

## Why not just a directory on the btrfs pool

Two reasons, and only the first is fixable without repartitioning.

**1. The pool's mount options are wrong for this workload.** `/`, `/nix` and
`/home` mount `compress=zstd:1`, and btrfs cannot do O_DIRECT on compressed
extents — it silently falls back to buffered I/O. Upstream measures O_DIRECT as
a large win on drives with DRAM and bandwidth headroom (4.25 → 9.69 GB/s in
their `iobench` on a GB10), so losing it outright is not a rounding error.
int4 weights are incompressible noise anyway, so zstd is pure CPU cost on write
plus a decompress step in the read hot path, and CoW + per-read csum
verification are dead weight on a read-only 400+ GB blob.

This part *could* have been solved in place with `chattr +C` on a directory —
nodatacow, which also disables compression and checksums for files created
inside it. It was rejected because the flag only applies to files created
*after* it is set, so the correctness of a 400+ GB download would depend on a
tmpfiles rule having fired first. ext4 has none of these knobs to get wrong,
which is the actual argument: the weights *cannot* end up compressed because the
filesystem does not implement compression.

**2. The dual-drive path needs two filesystems, and that is the real prize.**
colibrì's `COLI_MODEL` + `COLI_MODEL_MIRROR` mode hashes each expert to one of
two drives and **sums their read bandwidth**. Decode is disk-bound here, so this
is the single largest throughput lever available. It routes by path, so it needs
two independent filesystems on two physical drives — two directories on one
btrfs pool would be two reads of the same filesystem for double the space and no
gain. `-d single` spreads chunks across both devices, but you cannot direct it,
verify it, or read per-drive stats off it.

## Layout

| Device | Partition | Size | Contents | Changed? |
|---|---|---|---|---|
| nvme0n1 — Samsung **980** | p1 | 1 G | ESP (`/boot`, shared with Windows) | — |
| | p2 | 930 G → **730 G** | btrfs pool member | shrunk |
| | **p3** | **~200 G** | **ext4 → `/llm/mirror`** | **new** |
| nvme1n1 — Samsung **970 EVO** | p1 | 150 G | NTFS slot (Windows/League) | — |
| | p2 | 780 G → **381 G** | btrfs pool member, owns the mkfs | shrunk |
| | **p3** | **~400 G** | **ext4 → `/llm/primary`** | **new** |

btrfs pool drops from ~1.7 TB to ~1.1 TB usable.

**Nothing is renumbered.** The ESP stays p1, Windows stays `nvme1n1p1` (named in
`configuration.nix` and `scripts/saturn-windows-image.sh`), and the btrfs
`extraArgs` still points at `${ssdA}-part2`. That falls out of putting the LLM
partitions last, which is also what makes the in-place migration possible.

The pool members carry explicit sizes rather than `size = "100%"` — a 100%
partition sorts last in disko and nothing can follow it. The LLM partitions take
`100%` instead, absorbing whatever the drive actually has past the pool; the
exact usable capacity of a "1 TB" NVMe isn't worth hardcoding, and a few hundred
MiB either way is noise against a 400 G model.

Every partition also carries an explicit `priority`: disko orders by priority and
falls back to attribute-name order for ties, and `builtins.sort` guarantees no
stability, so leaving ties to break by name would make the numbering an
implementation detail.

### Why the sizes are asymmetric

The drives are not equals for this workload:

- **970 EVO** — TLC with a 1 GB LPDDR4 DRAM cache. The better streaming drive,
  especially for the scattered random reads expert routing generates. Gets the
  **400 G primary**, which serves every expert the mirror does not hold.
- **980 (non-Pro)** — TLC but **DRAM-less** (HMB). Upstream specifically warns
  that `DIRECT=1` is "neutral to negative" on DRAM-less and QLC drives. Gets the
  **200 G mirror**.

Both are PCIe 3.0 (~3.5 GB/s each), so a full split tops out around 7 GB/s.

400/200 covers both models worth running here:

| Model | Total | Active/token | Primary | Mirror |
|---|---|---|---|---|
| **DeepSeek V4 Flash** | 167 G | 13B | full | **full** → ~50/50 split |
| **GLM-5.2** (chosen) | 419 G | 40B | full, 2.8 GB spare | ~48% partial |

colibrì weights routing by *measured* per-drive bandwidth, so it handles the
asymmetric pair itself — no manual `COLI_DISK_WEIGHTS` needed.

## In place, no reinstall

**Deploying this config does not repartition anything.** `nixos-rebuild` / `nh os
switch` never runs disko's format script — that only happens during a fresh
install via nixos-anywhere or `disko-install`. Switching to this config on the
running saturn just adds two `fileSystems` entries, both `nofail`, which sit
inert until the filesystems exist. The surgery below is what brings the disk into
agreement with what `disko.nix` already declares.

### Precondition — measured 2026-08-16

```
Device size: 1.67TiB   Used: 516.57GiB   (data 502.17G single, metadata 7.20G raid1)
devid 1  /dev/nvme1n1p2  (970 EVO)  size 781.51GiB  used 198.01GiB
devid 2  /dev/nvme0n1p2  (980)      size 930.51GiB  used 348.01GiB
```

Post-shrink the pool is 730 + 381 = 1111 GiB against 502 GiB of data, leaving
~595 GiB free, and both members have 580+ GiB unallocated for btrfs to relocate
into. It fits with a lot of room. Re-check with `btrfs filesystem usage /` before
starting if much time has passed.

> **devid 1 is the 970 EVO and devid 2 is the 980** — the opposite of what the
> nvme0/nvme1 numbering suggests. Getting these backwards shrinks the wrong drive.

### Phase 1 — online, on the running system

btrfs shrinks a member device while mounted, relocating chunks off the tail. This
is the only part that moves data. It is interruptible and restartable, and
reversible with `resize <devid>:max` right up until Phase 2.

**This must happen before Phase 2.** Repartitioning first would truncate a
filesystem that still believes it owns the full device — that is the one way to
lose data here.

devid 2 is nvme0n1p2 (the 980) and devid 1 is nvme1n1p2 (the 970 EVO). No inline
`#` comments below — saturn's zsh does not have `interactive_comments` set, so a
trailing comment is passed to btrfs as arguments and the command fails with
"exactly 2 arguments expected".

```bash
sudo btrfs filesystem resize 2:730G /
sudo btrfs filesystem resize 1:381G /
btrfs filesystem show /
```

`show` must report 730.00GiB for devid 2 and 381.00GiB for devid 1. Do not
proceed until it does.

### Phase 2 — live, then one reboot

No installer media needed. A GPT lives in LBA 0–33 with its backup in the last 33
sectors of the disk, and neither is inside any partition — on both drives p2 ends
at 1953523711 with the disk running to 1953525167, so the backup header sits in
the gap past it. `sgdisk` can therefore rewrite the table on a running system.

What it *cannot* do is make the kernel re-read that table while partitions are
mounted; it will say so and tell you to reboot. That is fine and expected here,
because the only in-use partition being changed is p2 and btrfs has already been
shrunk inside it — the kernel's stale, too-large view of p2 is inert until the
reboot corrects it. Nothing writes past 730/381 GiB in the meantime.

Have the earlier `--backup` files somewhere you can reach from rescue media
anyway, since the reboot is the moment a bad table would bite.

`sgdisk` is not in saturn's system closure — `nix shell nixpkgs#gptfdisk` first.

Back the tables up before touching anything:

```bash
sgdisk --backup=/tmp/nvme0n1.gpt /dev/nvme0n1     # --load-backup= to undo
sgdisk --backup=/tmp/nvme1n1.gpt /dev/nvme1n1
```

`sgdisk --delete` only rewrites the partition table; it does not touch filesystem
data. Recreating p2 at an identical start sector with a smaller size leaves the
btrfs member exactly where it was.

Sectors below are absolute and measured off saturn (512-byte sectors, both drives
ending at 1953523711). They are spelled out rather than using `+730G` so the
arithmetic is auditable and `--align-end` cannot shift an end sector out from
under a filesystem — every boundary here is already 1 MiB aligned.

```bash
# 980 / nvme0n1 — p2 start 2099200 (1.0 GiB), p2 → 730 GiB, p3 → /llm/mirror (~200 GiB)
sgdisk --delete=2 \
       --new=2:2099200:1533020159    --typecode=2:8300 --change-name=2:disk-ssd_a-pool \
       --new=3:1533020160:1953523711 --typecode=3:8300 --change-name=3:disk-ssd_a-llm \
       /dev/nvme0n1

# 970 EVO / nvme1n1 — p2 start 314574848 (150.0 GiB), p2 → 381 GiB, p3 → /llm/primary (~400 GiB)
sgdisk --delete=2 \
       --new=2:314574848:1113589759  --typecode=2:8300 --change-name=2:disk-ssd_b-pool \
       --new=3:1113589760:1953523711 --typecode=3:8300 --change-name=3:disk-ssd_b-llm \
       /dev/nvme1n1
```

The p2 start sectors (2099200 and 314574848) are the load-bearing values — they
must match what the drives already have, and they are what `sgdisk --info=2`
reported. The p2 end sectors give exactly 730 and 381 GiB, matching Phase 1.

The partition **names are not cosmetic** — `fileSystems` mounts everything by
`by-partlabel`. `disk-ssd_a-pool` and `disk-ssd_b-pool` are the labels the
existing partitions already carry and must be reproduced exactly; `disk-ssd_a-llm`
and `disk-ssd_b-llm` are what the new config expects.

`sgdisk` will warn that the kernel is still using the old table. Reboot normally
into NixOS — no rescue media — and it comes up with the new one. Then the
filesystems, matching what disko would have created (`-m 0`, no other flags):

```bash
sudo mkfs.ext4 -m 0 /dev/disk/by-partlabel/disk-ssd_a-llm
sudo mkfs.ext4 -m 0 /dev/disk/by-partlabel/disk-ssd_b-llm
```

### Phase 3 — back into NixOS

```bash
nh os switch
findmnt /llm/primary /llm/mirror
btrfs filesystem show /
```

### If it goes wrong

Phase 1 is fully reversible until Phase 2 rewrites the table. The one step worth
re-reading before pressing enter is the p2 start sector: get it wrong and the
pool won't mount, because btrfs will be looking at the wrong offset. No data has
moved at that point, so restoring the correct start — or
`sgdisk --load-backup=/tmp/nvme0n1.gpt` — brings it straight back. Do not run
`mkfs` on anything but p3.

## Or: from scratch

A fresh install via nixos-anywhere produces the identical layout with no manual
steps, since `disko.nix` declares exactly what Phase 2 builds by hand. Follow
[saturn-disko-migration.md](saturn-disko-migration.md) as written. Only worth it
if saturn is being rebuilt for other reasons.

## Status as of 2026-08-16

Storage migration **done** — both partitions exist, mounted, and the pool
shrank cleanly. GLM-5.2 is downloaded to `/llm/primary/glm52-i4`.
`serve.enable` is still `false`. Open problems are listed under
[Known problems](#known-problems) — read those before doing anything else.

## Model choice: GLM-5.2

Chosen over DeepSeek V4 Flash. V4 Flash is the safer fit on paper — 167 G, 16 GB
RAM, and 13B active parameters per token against GLM's 40B, which is what sets
decode speed on a disk-bound box — but GLM-5.2 is the strongest model this
hardware can physically hold, and capability won out over speed.

Kimi K3 leads the open-weight leaderboards but is 1.6 TB and cannot fit. Inkling
(975B, 469 G) fits the disk only with a 500 G primary and wants ~25 GB RAM
against saturn's 22 GB available, so it is out on memory regardless.

**The 372 GB figure in upstream's README is wrong for this container.** The real
`mastouri/GLM-5.2-colibri-int4-g64-with-int8-mtp` is **419.3 GB across 141
shards** — about 390 GiB, against a 400.5 GiB partition. That is why the primary
is now at 2.8 GB free. The 400 G partition size was chosen off the README figure;
it fits, but with no headroom worth speaking of.

## Staging the weights

`coli convert` is the wrong path. It pulls `zai-org/GLM-5.2-FP8` — 756 GB of
source shards — and requantises locally, needing numpy + torch + huggingface_hub
and hours of CPU. The prebuilt container is the same result for half the bytes
and no torch:

```bash
nix shell nixpkgs#python3Packages.huggingface-hub
hf download mastouri/GLM-5.2-colibri-int4-g64-with-int8-mtp \
  --local-dir /llm/primary/glm52-i4
```

Resumable. **Do not run this under sudo** — see [Known problems](#known-problems).

Afterwards the MTP head must be the int8 one, or speculative decoding silently
never fires (upstream measured 0–4% draft acceptance at int4 versus 39–59%):

```bash
ls -l /llm/primary/glm52-i4/out-mtp-*
```

must be `3527131672 / 5366238584 / 1065950496`. `hf download` also leaves a
`.cache/` staging directory in the target — safe to delete once verified, and
worth doing at 2.8 GB free.

## Bringing it up

`myNixOS.services.colibri.enable = true` is already set, so `coli` is on PATH.

```bash
# 1. Is this box actually ready? Read-only, safe to run any time.
coli doctor --deep --model /llm/primary/glm52-i4
coli plan --model /llm/primary/glm52-i4   # planned VRAM/RAM/disk placement

# 3. Run some REPRESENTATIVE prompts before mirroring. The engine records which
#    experts your workload actually routes to in .coli_usage, updated every turn,
#    and the partial-mirror planner ranks shards off that history. Staging on a
#    cold .coli_usage ranks on nothing.
coli chat

# 4. Mirror the hottest half onto the second drive. GLM-5.2 is 372G against a
#    200G mirror, so this is necessarily partial. Staging never touches the
#    primary: it copies through temp files, SHA-256s every shard, honours the
#    free-space reserve, never deletes an existing mirror shard, and publishes a
#    receipt only once the selected set is complete.
coli mirror plan   --model /llm/primary/glm52-i4 --mirror /llm/mirror/glm52-i4 \
  --budget-gib 180 --reserve-gib 10
coli mirror stage  --model /llm/primary/glm52-i4 --mirror /llm/mirror/glm52-i4 \
  --budget-gib 180 --reserve-gib 10
coli mirror verify --model /llm/primary/glm52-i4 --mirror /llm/mirror/glm52-i4

# 5. Measure. Do not guess.
coli tune
```

`--budget-gib 180 --reserve-gib 10` fits the 200.5 GiB mirror partition with room
for ext4 overhead. The mirror is re-stageable at any time and gets *better* the
longer colibrì has been used, since `.coli_usage` keeps learning — so restaging
after a few weeks of real work is worth doing.

Then set `serve.enable = true`, point `model`/`mirror` at those paths, and put
whatever `tune` measured into `serve.environment` so the tuned profile is
declarative rather than one machine's shell history.

## Known problems

Open as of 2026-08-16, in the order they should be dealt with.

**1. `/llm/primary` has 2.8 GB free.** The container is 419.3 GB, not the 372 GB
the README claims. Delete `.cache/` in the model directory first. If that is not
enough, the honest options are dropping to a smaller model or re-doing the
partition split with a larger primary (which is another live migration, not a
config change).

**2. The model directory is root-owned, so persistence is disabled.**
`coli doctor` reports `[warn] storage.persistence  model directory is
read-only`. That comes from downloading under `sudo`. It matters more than it
looks: `.coli_usage` is written *next to the model*, and it is both the learning
cache that raises the expert hit rate over time and the ranking input for
`coli mirror plan`. Until this is fixed, colibrì cannot get faster with use and
the mirror cannot be staged sensibly.

```bash
sudo chown -R cramt:users /llm/primary /llm/mirror
```

Note the container ships its own `.coli_usage`, so mirror planning would rank on
the uploader's workload rather than nothing — but that is not your workload.

**3. No GPU detected.** `coli doctor` says `no supported GPU detected` and the
plan reads `VRAM no NVIDIA device detected · CPU path`, on a machine running a
gfx1101 HIP build. `resource_plan.py` probes `nvidia-smi`, then falls back to
`rocm-smi`; neither is on PATH, so it plans CPU-only and the entire 16 GB VRAM
tier goes unused. The package now puts `rocm-smi` on `coli`'s PATH for the
`rocm` variant. If it still mis-detects after that, upstream marks
`_discover_amd_gpus` "hardware-owner-needed — authored without a ROCm host to
test against" (#662), so it is worth reporting rather than working around.

**4. Projected expert residency is 1%.** With the CPU-only plan: 20.9 GB RAM
budget, 11.6 GB dense, 6.3 GB runtime, and only **3.1 GB of warm experts against
404.6 GB of cold ones**, cap 1/layer. `limit disk expert misses`. Essentially
every expert read goes to disk, so expect roughly **0.3 tok/s**, not the 1–3 this
document estimated before any of it was measured. Fixing 3 should improve this
materially, since the VRAM tier is currently contributing nothing.

colibrì's own auto-tune, at that hit rate, recommends:

```
DRAFT=0    low hit rate: MTP widens expert union, adds disk reads
PIPE=1     overlap disk reads with resident expert compute
```

Note `DRAFT=0` disables the MTP speculative drafting the int8 head exists for —
at a 1% hit rate the wider expert union costs more in disk reads than the drafts
save. That should be revisited once residency is up.

## What still needs measuring

Three open questions, all empirical, none answerable from the couch. Upstream
asks for hardware, commit, model, exact command, prompt, cache state and
throughput when reporting numbers — worth doing, since a 7800 XT + dual-PCIe-3.0
pair is not a configuration they have data for.

**HIP vs Vulkan.** Both variants are built (`colibri-rocm`, `colibri-vulkan` in
`overlays/default.nix`) and selectable via `backend`. Upstream measures the
Vulkan int4 expert primitive ~35% *faster* than ROCm/HIP on an RX 9070 — but
that is RDNA4. gfx1101 is RDNA3 and properly ROCm-supported, so that result does
not transfer, and RDNA3's WMMA matrix cores are exactly what the rocWMMA path
targets. Flip `backend` between `"rocm"` and `"vulkan"` and compare.

**`DIRECT=1`.** Should win on the 970 EVO (DRAM, headroom) and may well lose on
the DRAM-less 980. `serve.direct` is off by default for that reason. Note this
knob is per-*service*, not per-drive, so if the two disagree the mirror split
itself is what to re-examine.

**Whether 31 GiB of RAM is the real ceiling.** Measured free on an idle-ish
desktop: 22 GiB available of 31 GiB total, plus 15 GiB of zram. V4 Flash wants 16
GB minimum / 22 comfortable, which fits; GLM-5.2 wants 24 comfortable, which does
not without closing things; Inkling wants ~25 GB even with the reduced dense
container, so it is the marginal one despite fitting on disk. `serve.memoryMax`
exists precisely so an overshoot degrades instead of taking the session down.
Saturn also has the unresolved Bank-0 MCEs (see `saturn-mce-bios.md`) — holding
20+ GB resident for hours is a good way to find out whether those are still there.

**Not** open: the `march` question. Saturn is an i7-10700K (Comet Lake) with AVX2
but no AVX-512 and no AVX-VNNI, so there is no VNNI dot kernel to unlock and the
package's `x86-64-v3` default is already the correct target.

## Expected throughput

No end-to-end token has been generated yet, so there is still no measured
number. Treat everything here as an estimate until `coli tune` says otherwise.

The pre-measurement guess was 1–3 tok/s for V4 Flash and under 1 for GLM-5.2,
extrapolated from upstream's 1.07 tok/s on a single 12 GB RTX 5070 Ti. That was
too optimistic for the configuration as it actually stands: `coli plan` projects
**1% expert residency** with the GPU undetected, which puts GLM-5.2 nearer
**0.3 tok/s** — roughly 11 GB of routed experts per token off a single ~3.5 GB/s
drive, with almost no cache absorbing it.

Three things should move that number, in rough order of expected effect:

1. **Getting the GPU detected** (problem 3) — the 16 GB VRAM tier currently
   contributes nothing to residency.
2. **Staging the mirror** — splits expert reads across both drives instead of
   hammering the 970 EVO alone.
3. **Letting `.coli_usage` learn** (problem 2) — residency rises as the pinned
   hot-set matches the actual workload.

Even so, this is "ask it something and come back", not chat. That is the honest
ceiling for streaming a 744B model off consumer PCIe 3.0 NVMe.
