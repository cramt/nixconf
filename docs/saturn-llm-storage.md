# Saturn LLM streaming tier

Dedicated NVMe partitions for [colibrì](https://github.com/JustVugg/colibri), which
runs frontier MoE models by streaming expert weights off disk instead of holding
them in RAM. Declared in `hosts/saturn/disko.nix`; consumed by
`myNixOS.services.colibri` (`modules/services/colibri.nix`).

**Adding these partitions is a full reinstall** — disko repartitions and wipes
both SSDs. Follow [saturn-disko-migration.md](saturn-disko-migration.md); the
backup list and procedure there are unchanged.

## Why not just a directory on the btrfs pool

Two reasons, and only the first is fixable without repartitioning.

**1. The pool's mount options are wrong for this workload.** `/`, `/nix` and
`/home` mount `compress=zstd:1`, and btrfs cannot do O_DIRECT on compressed
extents — it silently falls back to buffered I/O. Upstream measures O_DIRECT as
a large win on drives with DRAM and bandwidth headroom (4.25 → 9.69 GB/s in
their `iobench` on a GB10), so losing it outright is not a rounding error.
int4 weights are incompressible noise anyway, so zstd is pure CPU cost on write
plus a decompress step in the read hot path, and CoW + per-read csum
verification are dead weight on a read-only 167–372 GB blob.

This part *could* have been solved in place with `chattr +C` on a directory —
nodatacow, which also disables compression and checksums for files created
inside it. It was rejected because the flag only applies to files created
*after* it is set, so the correctness of a 372 GB download would depend on a
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

| Device | Partition | Size | Contents |
|---|---|---|---|
| nvme0n1 — Samsung **980** | p1 | 1 G | ESP (`/boot`, shared with Windows) |
| | **p2** | **200 G** | **ext4 → `/llm/mirror`** |
| | p3 | rest (~730 G) | btrfs pool member |
| nvme1n1 — Samsung **970 EVO** | p1 | 150 G | NTFS slot (Windows/League) |
| | **p2** | **400 G** | **ext4 → `/llm/primary`** |
| | p3 | rest (~380 G) | btrfs pool member, owns the mkfs |

btrfs pool drops from ~1.7 TB to ~1.1 TB usable.

Partition **numbers are load-bearing** and every partition now carries an
explicit `priority`. disko orders by priority and falls back to attribute-name
order for ties, and `builtins.sort` guarantees no stability — so leaving ties to
break by name would make the numbering an implementation detail. Two things
depend on it:

- the btrfs `extraArgs` reference to `${ssdA}-part3` (was `-part2`)
- `nvme1n1p1` for Windows, named in `configuration.nix` and
  `scripts/saturn-windows-image.sh` — which is why the NTFS slot keeps
  priority 100 and the LLM partition goes *after* it

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
| GLM-5.2 | 372 G | 40B | full | ~54% partial |

colibrì weights routing by *measured* per-drive bandwidth, so it handles the
asymmetric pair itself — no manual `COLI_DISK_WEIGHTS` needed.

## Start with DeepSeek V4 Flash

Not GLM-5.2, despite GLM being upstream's reference model. V4 Flash is 167 G
rather than 372 G, wants 16 GB RAM rather than 24, and — the part that actually
matters — activates **13B parameters per token against GLM's 40B**. Bytes
streamed per token is what sets decode speed on a disk-bound box. It also fits
on *both* partitions, so it gets a full mirror and a clean ~50/50 bandwidth
split, where GLM only gets a partial one.

## After the reinstall

Nothing below is automated, because staging 167 GB and measuring a machine are
not things to do from a NixOS activation script.

`myNixOS.services.colibri.enable = true` is already set, so `coli` is on PATH
from first boot; `serve.enable` is deliberately `false` until weights exist.

```bash
# 1. Is this box actually ready? Read-only, safe to run before anything else.
coli doctor
coli plan --model /llm/primary/deepseek-v4-flash   # planned VRAM/RAM/disk placement

# 2. Stage the weights onto the primary (one-time, ~167 GB).
coli convert --model /llm/primary/deepseek-v4-flash

# 3. Mirror onto the second drive. V4 Flash fits whole, so this is a full copy;
#    `plan` ranks shards by how hot their experts are for the partial case.
coli mirror plan   --model /llm/primary/... --mirror /llm/mirror/...
coli mirror stage  --model /llm/primary/... --mirror /llm/mirror/...
coli mirror verify --model /llm/primary/... --mirror /llm/mirror/...

# 4. Measure. Do not guess.
coli tune
```

Then set `serve.enable = true`, point `model`/`mirror` at those paths, and put
whatever `tune` measured into `serve.environment` so the tuned profile is
declarative rather than one machine's shell history.

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

**Whether 32 GB of RAM is the real ceiling.** V4 Flash wants 16 GB minimum, 22
comfortable, on a desktop that also runs COSMIC and games, with
`vm.swappiness = 180` and zram in the mix. `serve.memoryMax` exists precisely so
an overshoot degrades instead of taking the session down. Saturn also has the
unresolved Bank-0 MCEs (see `saturn-mce-bios.md`) — holding 20+ GB resident for
hours is a good way to find out whether those are still there.

## Expected throughput

Roughly **1–3 tok/s** for V4 Flash on this hardware, extrapolating from
upstream's 1.07 tok/s for a single 12 GB RTX 5070 Ti on GLM-5.2 — saturn has
more VRAM (16 GB) and a model with a third of the active parameters, against
slower PCIe 3.0 storage. GLM-5.2 would land lower, likely under 1 tok/s.

This is "ask it something and come back", not chat. That is the honest ceiling
for streaming a frontier model off consumer SATA-class NVMe, and no amount of
partitioning changes it — the partitions are what get you the top of that range
instead of the bottom.
