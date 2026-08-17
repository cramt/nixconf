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

| Drive | Partition | Size | Contents | Changed? |
|---|---|---|---|---|
| Samsung **980** (`ssdA`) | p1 | 1 G | ESP (`/boot`, shared with Windows) | — |
| | p2 | 930 G → **730 G** | btrfs pool member | shrunk |
| | **p3** | **200.5 G** | **ext4 → `/llm/mirror`** | **new** |
| Samsung **970 EVO** (`ssdB`) | p1 | 150 G | NTFS slot (Windows/League) | — |
| | p2 | 780 G → **381 G** | btrfs pool member, owns the mkfs | shrunk |
| | **p3** | **400.5 G** | **ext4 → `/llm/primary`** | **new** |

btrfs pool drops from ~1.7 TB to ~1.1 TB usable.

> **Drives are identified by model, not by `nvmeXn1`.** As of 2026-08-17 the
> kernel enumerates the **970 EVO as `nvme0n1`** and the **980 as `nvme1n1`** —
> the reverse of what the migration section below assumes, and the reverse of
> what an earlier version of this table claimed. Nothing real depends on the
> node names: `disko.nix` addresses by-id, `fileSystems` by-partlabel, and both
> Windows scripts by `<ssd_b by-id>-part1`. But do not copy a `/dev/nvmeXn1` out
> of this document without re-checking `lsblk -o NAME,SIZE,PARTLABEL,MOUNTPOINT`
> first — the Phase 2 commands below are `sgdisk` invocations against whole
> disks, and the two are not interchangeable.

**Nothing is renumbered.** The ESP stays p1, Windows stays the 970 EVO's p1
(addressed by-id in `scripts/saturn-windows-image.sh` and
`scripts/windows-vm.sh`), and the btrfs `extraArgs` still points at
`${ssdA}-part2`. That falls out of putting the LLM partitions last, which is also
what makes the in-place migration possible.

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
| **GLM-5.2** (chosen) | 429 G | 40B | shards only, 2.7 GiB spare | 64/141 shards |

GLM-5.2 is the tight one: 419 G of shards fit the primary, the 10 G int8 MTP head
does not, and the mirror takes the hottest 180 GiB of shards
([Known problems](#known-problems)).

colibrì weights routing by *measured* per-drive bandwidth, so it handles the
asymmetric pair itself — no manual `COLI_DISK_WEIGHTS` needed.

## In place, no reinstall

> **This was carried out on 2026-08-16 and is kept as a record, not a
> to-do.** Both partitions exist and are mounted. Every `/dev/nvmeXn1` below is
> the enumeration *as it was that day*, and today's is the reverse of it (see the
> note under [Layout](#layout)) — so if this ever needs re-running on a different
> box or after a disk swap, re-derive every node name and sector from `lsblk` and
> `sgdisk --info` first. These are whole-disk `sgdisk` commands; the wrong node is
> the wrong drive.

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

## Status as of 2026-08-17

- Storage migration **done** — both partitions exist, mounted, pool shrank
  cleanly.
- GLM-5.2 **downloaded** to `/llm/primary/glm52-i4`: all 141 shards, **minus the
  int8 MTP head**, which does not fit (problem 1).
- **It generates tokens: 0.18 tok/s** with the mirror, up from 0.13 without.
  Both CPU-only — a bare `coli` run does not use the GPU on Linux, see
  [the flag trap](#the-gpu-flag-trap--read-this-before-trusting-any-number).
- GPU detection **fixed and deployed** — `coli doctor` reports `[ok]
  accelerator.gpu`, 13.4 GB hot tier, projected residency 1% → 4% (problem 3).
- Mirror **staged and verified** 2026-08-17: 64 of 141 shards, 193,110,254,368
  bytes on the 980, `coli mirror verify` → `ready: true`, zero failures.
- `serve.enable` is **true**, started by hand rather than at boot — see
  [Running it as a service](#running-it-as-a-service). Nothing has been through
  `coli tune` yet.

Read [Known problems](#known-problems) before doing anything else.

## Model choice: GLM-5.2

Chosen over DeepSeek V4 Flash. V4 Flash is the safer fit on paper — 167 G, 16 GB
RAM, and 13B active parameters per token against GLM's 40B, which is what sets
decode speed on a disk-bound box — but GLM-5.2 is the strongest model this
hardware can physically hold, and capability won out over speed.

Kimi K3 leads the open-weight leaderboards but is 1.6 TB and cannot fit. Inkling
(975B, 469 G) fits the disk only with a 500 G primary and wants ~25 GB RAM
against saturn's 22 GB available, so it is out on memory regardless.

**The 372 GB figure in upstream's README is wrong for this container, and so is
the 419.3 GB one this document used to give.** Per the HF API, the real
`mastouri/GLM-5.2-colibri-int4-g64-with-int8-mtp` is **429.3 GB**:

| Part | Bytes | |
|---|---|---|
| 141 × `out-*.safetensors` | 419,316,897,273 | downloaded |
| 1 × `out-mtp-00000.safetensors` | 9,959,321,520 | **does not fit** |
| **total** | **429,276,218,793** | |

The 400.5 GiB partition gives 394 GiB (423 GB) usable after ext4 overhead, so the
shards alone leave **2.7 GiB free** and the MTP head is ~7 GB more than the drive
has left. The 400 G size was chosen off the README's 372 GB; it fits the shards
and nothing else. See [Known problems](#known-problems).

`out-00136.safetensors` is **16 bytes** — an empty safetensors header (`{}`).
That is what upstream ships (the HF API reports 16 bytes too), not a truncated
download. Do not "repair" it.

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

The container's whole point over a plain int4 repo is that its MTP head is int8,
without which speculative decoding silently never fires (upstream measured 0–4%
draft acceptance at int4 versus 39–59%). It is a **single** file:

```bash
ls -l /llm/primary/glm52-i4/out-mtp-00000.safetensors   # must be 9959321520
```

**On saturn this file is absent** — it does not fit next to the shards, and the
mirror partition is where it would have to live. Nothing is lost yet: at the
current hit rate `coli plan` recommends `DRAFT=0` anyway, which disables the
drafting the int8 head exists for. Revisit once residency is up
([Known problems](#known-problems)).

`hf download` also leaves a `.cache/` staging directory in the target — safe to
delete once verified, and on this partition not optional.

## Bringing it up

`myNixOS.services.colibri.enable = true` is already set, so `coli` is on PATH.

```bash
# 1. Is this box actually ready? Read-only, safe to run any time.
coli doctor --deep --model /llm/primary/glm52-i4
coli plan --model /llm/primary/glm52-i4   # planned VRAM/RAM/disk placement

# 2. Run some REPRESENTATIVE prompts before mirroring. The engine records which
#    experts your workload actually routes to in .coli_usage, updated every turn,
#    and the partial-mirror planner ranks shards off that history. The container
#    ships its own .coli_usage, so a cold one ranks on the uploader's workload
#    rather than on nothing — still not yours.
coli chat

# 3. Mirror the hottest shards onto the second drive. GLM-5.2 is 419G of shards
#    against a 200G mirror, so this is necessarily partial (64 of 141 shards at
#    --budget-gib 180). Staging never touches the primary: it copies through temp
#    files, SHA-256s every shard, honours the free-space reserve, never deletes an
#    existing mirror shard, and publishes a receipt only once the selected set is
#    complete. Budget ~25 min and expect a long silence first: it SHA-256s the
#    whole 180 GiB source set before writing a byte, then hashes each copy in
#    flight AND re-reads the written file to hash it again. That is three passes
#    over 180 GiB at ~500 MB/s, which is what Comet Lake does without SHA-NI —
#    the drives are not the limit here, the CPU is. `verify` re-hashes the whole
#    staged set against the receipt, so budget it another ~7 min; neither command
#    prints progress, so watch `df -h /llm/mirror` if you want a pulse.
coli mirror plan   --model /llm/primary/glm52-i4 --mirror /llm/mirror/glm52-i4 \
  --budget-gib 180 --reserve-gib 10
coli mirror stage  --model /llm/primary/glm52-i4 --mirror /llm/mirror/glm52-i4 \
  --budget-gib 180 --reserve-gib 10
coli mirror verify --model /llm/primary/glm52-i4 --mirror /llm/mirror/glm52-i4

# 4. Measure. Do not guess. --auto-tier is what makes it a GPU run at all (see
#    the flag trap under Measured throughput); `tune` sets it for you.
COLI_MODEL_MIRROR=/llm/mirror/glm52-i4 CUDA_RELEASE_HOST=1 \
  coli run "..." --model /llm/primary/glm52-i4 --auto-tier --vram 10
coli tune
```

`--budget-gib 180 --reserve-gib 10` fits the 200.5 GiB mirror partition with room
for ext4 overhead: measured, it selects **179.8 GiB and leaves 16.4 GiB free** —
which is also the space the int8 MTP head would need if problem 1 gets solved
that way, so do not raise the budget without deciding that question first. The
mirror is re-stageable at any time and gets *better* the longer colibrì has been
used, since `.coli_usage` keeps learning — so restaging after a few weeks of real
work is worth doing.

## Running it as a service

`serve.enable = true` as of 2026-08-17, and this is the better way to test:
`coli run` reloads 10.6 GB of dense weights on every invocation (~26 s) and
discards the warm expert cache, while the daemon keeps its LRU warm across
prompts — which at a 2% hit rate is the whole game.

**It does not start at boot** (`serve.autoStart = false`). GLM-5.2 needs ~20 GB
of *available* RAM and a logged-in session routinely leaves less, in which case
the engine refuses to start rather than risk being OOM-killed mid-generation.
That is a correct refusal, not a bug, and it is why the unit is started by hand:

```bash
free -g                      # `available` needs to be ~20+; close things if not
systemctl start colibri
journalctl -fu colibri       # watch for the [CUDA] line — that is a GPU run
```

Then talk to it — OpenAI-compatible, loopback only, port from `port-selector`:

```bash
PORT=$(systemctl show colibri -p ExecStart --value | grep -oP '(?<=--port )\d+')
curl -s localhost:$PORT/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"glm52-i4","messages":[{"role":"user","content":"hi"}],"max_tokens":32}'
```

Expect minutes, not seconds. `systemctl stop colibri` gives the RAM back.

Two settings worth understanding before changing them:

- **`user = "cramt"`, not a system user.** `.coli_usage` lives next to the model,
  so the daemon and an interactive `coli chat` must be the same identity or they
  learn two separate histories — and a system user cannot write into a model
  directory a human downloaded. For the same reason the model directory is
  `ReadWritePaths`, not read-only: marking it read-only silently disables
  persistence, and `coli doctor` is the only place that would tell you.
- **`vram = 10`** of 16 GB. The planner takes 13.3 GB if you let it, which is
  enough to evict the compositor and kill Electron apps.

Put whatever `coli tune` measures into `serve.environment` so the tuned profile
is declarative rather than one machine's shell history.

## Known problems

State as of 2026-08-17, in the order they should be dealt with.

**1. `/llm/primary` has 2.7 GiB free, and the int8 MTP head is what does not
fit.** `.cache/` is already deleted and the model dir holds nothing else
droppable. The missing `out-mtp-00000.safetensors` is 9.96 GB against 2.7 GiB
free, so there is no rearranging the primary into fitting it — the options are:

- **Leave it out.** Costs nothing today: at this hit rate `coli plan` says
  `DRAFT=0`, so the drafting the head enables would be off anyway.
- **Put it on the mirror drive and symlink it in.** After staging at
  `--budget-gib 180` the mirror has ~16.4 GiB free, which fits. The engine opens
  weights by path, so a symlink from the model dir works, and the head's reads
  land on the *other* drive — which is where they want to be anyway. This is the
  move if `DRAFT=1` ever measures better.
- Re-do the partition split with a larger primary. Another live migration, not a
  config change, and it steals from the mirror — i.e. from lever #2.

**2. ~~The model directory is root-owned~~ — fixed.** `chown -R cramt:users
/llm/primary /llm/mirror` was applied; `.coli_usage` is now written next to the
model and growing (95 KB, 72,600 recorded selections). Persistence is live, so
the hit rate can improve with use and `coli mirror plan` has something to rank
on. Note that most of those selections are the **container's shipped
`.coli_usage`** — the uploader's workload, not yours — so restage the mirror once
saturn has real usage behind it.

**3. ~~No GPU detected~~ — fixed in `c91cc41`, deployed and verified
2026-08-17.** `coli doctor` now reports `[ok] accelerator.gpu  GPU engine and
devices are available`.

The cause was never upstream's detection logic: `resource_plan.py` probes
`nvidia-smi`, then falls back to `rocm-smi` (#662), and neither was on `coli`'s
PATH — so it planned CPU-only and the whole 16 GB VRAM tier went unused, on a
machine running a perfectly good gfx1101 HIP build.
`packages/colibri/default.nix` now `wrapProgram`s `rocmPackages.rocm-smi` onto
PATH for the `rocm` variant. Measured on the same engine binary, only PATH
differing:

| | without `rocm-smi` | with `rocm-smi` |
|---|---|---|
| VRAM | `no NVIDIA device detected · CPU path` | `13.2 GB hot tier · ~620 experts` |
| cold experts | 404.4 GB | 391.2 GB |
| projected residency | **1%** | **4%** |

The trap worth remembering: this looks exactly like a broken build, and it is a
missing runtime dependency of the *planner*. If it ever regresses, check
`ls $(dirname $(readlink -f $(which coli)))` for `.coli-wrapped` before
suspecting HIP.

Two cosmetic notes on the AMD path, neither breaking: `rocm-smi` prints
`Fail to open libdrm_amdgpu.so` on stderr, and the device name comes through as
`0:N/A` because this SKU reports `Card Series` as `N/A` (`_discover_amd_gpus`
prefers Series over Model). Upstream marks that function
"hardware-owner-needed — authored without a ROCm host to test against", and it
does parse saturn's CSV correctly, so both are worth reporting back.

**4. Projected expert residency is 4%, and it is still the ceiling.** Even with
the VRAM tier counted: 21.2 GB RAM budget, 11.6 GB dense, 6.3 GB runtime, 3.3 GB
warm experts, cap 2/layer, against 391.2 GB of cold experts. `limit disk expert
misses`. Nearly every expert read still reaches disk — see
[Measured throughput](#measured-throughput) for what that measured out at.

> The RAM budget is computed from **currently available** memory, not total, so
> `coli plan` and `coli doctor` give different answers depending on what else the
> desktop is doing — 21.2 GB budget / cap 2 per layer / 4% residency on an idle
> box, 19.9 GB / cap 1 / 0% while a mirror stage was running. Compare plans taken
> under the same conditions, and take the tuning ones on an idle machine.

colibrì's own auto-tune recommends, at this hit rate:

```
DRAFT=0             low hit rate: MTP widens expert union, adds disk reads
COLI_CUDA_PIPE=1    single GPU: S=1 pipeline gate
```

(`PIPE=1` was the CPU-plan recommendation; with the GPU detected it becomes
`COLI_CUDA_PIPE=1`.) `DRAFT=0` disables the MTP speculative drafting the int8
head exists for, which is the other reason problem 1 is not urgent.

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

**Whether 31 GiB of RAM is the real ceiling.** Partly answered: the first GLM-5.2
run sat at **13.7 GB RSS** against a 21.2 GB planned budget, on the CPU-only
plan — so it is not RAM-starved at this residency, it is disk-starved. Measured
free on an idle-ish desktop: 22 GiB available of 31 GiB total, plus 15 GiB of
zram. V4 Flash wants 16 GB minimum / 22 comfortable, which fits; GLM-5.2 wants 24
comfortable, which does not without closing things; Inkling wants ~25 GB even with the reduced dense
container, so it is the marginal one despite fitting on disk. `serve.memoryMax`
exists precisely so an overshoot degrades instead of taking the session down.
Saturn also has the unresolved Bank-0 MCEs (see `saturn-mce-bios.md`) — holding
20+ GB resident for hours is a good way to find out whether those are still there.

**Not** open: the `march` question. Saturn is an i7-10700K (Comet Lake) with AVX2
but no AVX-512 and no AVX-VNNI, so there is no VNNI dot kernel to unlock and the
package's `x86-64-v3` default is already the correct target.

## Measured throughput

Two runs, same prompt (`testing123`), 17 decoded tokens each, 2026-08-17.
**Both were CPU-only** — see the flag trap below; the gain is the mirror alone:

| | no mirror | verified mirror | GPU |
|---|---|---|---|
| decode | **0.13 tok/s** | **0.18 tok/s** (+38%) | not yet measured |
| expert hit rate | 2% | 2.3% (pin 0.0% + lru 2.3%) | |
| RSS | 13.7 GB | 13.69 GB | |
| MTP acceptance | — | 0% (0/0 — no head, see problem 1) | |

The second run's profile is the useful part:

```
prefill 8 tokens in 30.69s | decode 17 tokens in 95.59s
experts loaded/token: 600.0 (per-layer 8.00 across 75)
PROFILE: expert-disk 479.560s service / 69.976s wait | expert-matmul 11.009s
         | attention 11.830s | lm_head 0.000s | other 2.773s
MIRROR: primary 220.88 GB (41724 reads) | mirror1 56.43 GB (10658 reads)
        — 20% of expert bytes from the mirrors
```

Three things fall out of it, none of which were guessable up front:

**Compute is irrelevant and the design premise is confirmed.** Expert-disk
service time beats expert-matmul by ~44× and attention by ~40×. 277 GB of expert
reads for 17 tokens is **16 GB per token**, above the 11 GB this document
estimated. Nothing about this is a compute problem.

**The mirror is only pulling 20% of expert bytes while holding 45% of the
shards** — so the split is running at less than half its potential. This is the
`.coli_usage` caveat in problem 2 showing up as a number: the 64 shards were
ranked "hottest" using the *container's shipped* usage history, i.e. the
uploader's workload, and saturn's prompts route elsewhere. A restage against real
saturn history should move that 20% up substantially, and it is the cheapest
remaining lever — no config change, no repartition, just usage and ~25 min.

**The pinned hot-set is contributing nothing** (`pin 0.0% + lru 2.3%`): the entire
hit rate comes from LRU. Same root cause — the pin set is chosen off the same
unrepresentative history.

The drives are also not saturated: 277 GB across 126 s is ~2.2 GB/s aggregate,
with the 970 EVO at ~1.75 GB/s against its ~3.5 GB/s ceiling, and 70 s of the
95 s decode spent in disk *wait*. That gap is queue depth and read scatter, not
bandwidth, which is what `DIRECT=1` and the `PIPE`/`COLI_CUDA_PIPE` knobs exist
to attack — so `coli tune` has something real to chew on.

For reference, the pre-measurement guesses were 1–3 tok/s (extrapolated from
upstream's 1.07 tok/s on a 12 GB RTX 5070 Ti), then 0.3 tok/s once `coli plan`
projected 1% residency. Both were optimistic. The observed 2% hit rate did match
the planner's projection closely, so its residency figure is a trustworthy
predictor even where the throughput guesses were not.

### The GPU flag trap — read this before trusting any number

**On Linux a bare `coli chat` / `coli run` / `coli serve` is CPU-only, even on a
working HIP build with the GPU correctly detected.** The launcher's GPU
auto-enable path is scoped `sys.platform == "win32"`; on Linux nothing sets
`COLI_CUDA` unless you pass `--auto-tier` (or `--gpu`/`--vram`, which upstream
notes were themselves "silently ignored" without `--auto-tier`, causing "'GPU'
benchmarks published by mistake" — #121).

This is nastier than it sounds because **`coli doctor` still says
`[ok] accelerator.gpu`**: the *planner* sees the device and prints a VRAM tier,
while the *run* never touches it. Every number above was collected that way, and
the two are indistinguishable from the outside unless you look for a `[CUDA]`
line on stderr. With the flag, you get one:

```
[PLAN] RAM 8.3 GB · cap 0/layer · VRAM 13.3 GB
[CUDA] device 0: AMD Radeon RX 7800 XT, 17.2 GB VRAM, sm_110
[CUDA] mode: routed experts only (resident dense on CPU)
```

`modules/services/colibri.nix` therefore appends `--auto-tier` to the daemon's
ExecStart whenever `backend != "cpu"` — without it `serve.enable = true` would
have quietly served CPU-only forever. For manual runs, pass it yourself.

Two things follow immediately, both measured on the first `--auto-tier` attempt:

**The VRAM tier costs its size in host RAM as well.** `CUDA_RELEASE_HOST=0` is
the default and on a single GPU it keeps host copies of everything placed in
VRAM, which put the projected peak at **19.0 GB against 9.1 GB available** — and
the engine *refused to start* rather than be OOM-killed mid-generation, which is
the right call and worth knowing is a thing it does. Upstream:
`CUDA_RELEASE_HOST=1` "frees them for the RAM tier and is what this topology
usually wants" (#686). The module now sets it for every non-CPU backend.

**The planner will take nearly all your VRAM.** Left to size itself it claimed
13.3 of 16 GB and killed Discord outright. `serve.vram` exists for that: it is
`memoryMax`'s counterpart for VRAM, set to 10 on saturn to leave the desktop ~6
GB. Note the RAM budget in that run was only 8.3 GB *because* the desktop was
busy — this box cannot run a 20 GB engine and a normal session at once, and
`cap 0/layer` is what that looks like from the planner's side.

### The drives are not the ones the layout assumed

The first `--auto-tier` run printed a measured per-drive probe, and it inverts
the premise of the whole 400/200 split:

```
[MIRROR] probe: primary 0.23 GB/s | mirror 0.78 GB/s
[MIRROR] 2 drives | read split 23% / 77% (measured)
```

The **980 probes 3.4× faster than the 970 EVO**, and colibrì is routing 77% of
expert reads to the *mirror* accordingly — the opposite of the design intent,
which gave the 970 EVO the 400 G primary on the grounds that it was the better
streaming drive (DRAM cache vs the 980's HMB).

Do not rewrite the layout off this yet. The likely cause is that the primary is
**100% full** — 2.7 GiB free of 394 GiB — and a full TLC drive has no SLC cache
left to write into and a badly fragmented free list; 0.23 GB/s is also absurdly
low against the 970 EVO's ~3.5 GB/s spec, which smells like an artefact rather
than the drive's true ceiling. Things to separate before concluding anything:

- Re-probe when the box is idle (this one ran with the desktop busy).
- Benchmark both partitions directly (`coli iobench`, or plain `dd`/`fio` on a
  scratch file) rather than trusting a probe taken through a full filesystem.
- If it holds up, the fix is *not* a repartition: it is that the primary should
  not be run at 100%, which is the same finding as problem 1 from the other end.

Either way the engine is adapting on its own, which is what
`COLI_DISK_WEIGHTS`-by-measurement was supposed to buy — so this costs
throughput only to the extent that the *mirror* is the smaller drive.

### What is left to try, in order of measured promise

1. **Actually measure the GPU**, on an idle box with a closed desktop:
   `--auto-tier` plus `CUDA_RELEASE_HOST=1`, and free RAM above ~20 GB. Nothing
   above is a GPU number, so the size of that tier's contribution is still
   unknown.
2. **Use it, then restage the mirror.** The 20%-of-bytes figure is the whole
   argument: the ranking is currently the uploader's workload. `.coli_usage` is
   already learning — 72,600 selections at staging time, 102,000 after a bit of
   real chat — and a restage costs nothing but ~25 min.
3. **`coli tune`.** 70 s of the 95 s decode is disk *wait* at only ~2.2 GB/s of
   ~7 GB/s theoretical, so there is real headroom in `DIRECT`, `PIPE` /
   `COLI_CUDA_PIPE` and queue depth. It sets `--auto-tier` itself, so a tune run
   is a GPU run. Take it on an idle box, then put the result in
   `serve.environment`.
4. **Settle the drive-probe question** above before touching the layout.
5. **HIP vs Vulkan** — see [What still needs measuring](#what-still-needs-measuring).
6. **The int8 MTP head**, last: `MTP acceptance 0% (0/0)` is currently a
   tautology (there is no head), and auto-tune wants `DRAFT=0` regardless until
   the hit rate climbs. Only worth the 10 GB once the rest have moved residency.

Even at the optimistic end this stays "ask it something and come back", not chat.
That is the honest ceiling for streaming a 744B model off consumer PCIe 3.0 NVMe,
and 0.18 tok/s is the honest number today.
