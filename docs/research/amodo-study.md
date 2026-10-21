# Amodo's PoSE label generator on one H100: how it works, how fast it is, and what it means for WipeOS

*Study report, 2026-10-21. Code: [Amodo-Design/PoSE-Memory-Wiping](https://github.com/Amodo-Design/PoSE-Memory-Wiping) at `fae0935`.*

**How to read the evidence tags.** Every factual claim carries one:
- **[measured]:** we ran it on the H100.
- **[code]:** read in Amodo's source, with file and function given.
- **[inferred]:** our own reasoning or arithmetic. Treat these as hypotheses to check.

---

## Summary

**How labels are generated.**
- A label is a 32-byte keyed-BLAKE3 hash of a node's index, its one or two parent labels, a per-chunk seed derived from the challenge χ, and a graph descriptor.
- Nodes form the depth-robust graph of PoSE-DB (Bursuc et al. 2024). It is built recursively from butterfly networks, and its wiring is fixed by the chunk size m alone.
- For each chunk of m stored labels, the GPU hashes a hidden scaffold of about 276·m nodes (at m = 2^17, Amodo's setting) and keeps only m of them.
- The GPU gets its parallelism from labeling thousands of independent chunks at once. Within a chunk, 393,197 dependency levels must run in order.

**Headline throughput.**
- **0.81 GB/s (775 MiB/s) of stored labels on one H100 SXM** [measured]. That is 25.4 M labels/s, or 7.0 G node hashes/s, using Amodo's fastest strategy (`warp`) with windows sized to full batches.
- Labels are bitwise deterministic across runs, processes, strategies, window splits and CPU vs GPU [measured].

**Bottleneck.**
- The saturated kernel is **limited by integer arithmetic, i.e. the BLAKE3 hashing**, not by memory bandwidth: integer units about 79% busy, HBM traffic about 20% of peak [inferred from SASS and timing; hardware counters are blocked on this node].
- Further losses come from idle warp lanes on narrow graph levels (lane efficiency 0.88) and from partly filled final batches.

**Top two improvements, both measured, both byte-identical:**
1. **Precompute each node's χ-independent first BLAKE3 block once: +18–19%** (775 → 914–926 MiB/s), for 1.1 GB of GPU memory.
2. **Pinned host memory for DRAM and disk fills: +17% end to end** (host copies 4.3 → 55 GB/s).

**The neighborhood check (KR2.2): no.**
- In this graph, **every stored label has exactly one parent, and that parent is never stored**. It is a scaffold node, computed and discarded [measured on Amodo's own topology code: 131,072 of 131,072 outputs].
- An honest node therefore can't answer a candidate-C neighborhood query.
- Patching that by streaming the parents (or more scaffold) either fails to bind the values or costs on the order of **138–276 bytes of stream per byte stored**.
- **Our recommendation:** reconsider D16 rather than D18's design. A server that recomputes only a *secret random sample* of chunks, ahead of time while the fill runs, pays about **1.7 CPU-seconds per sample** at m = 2^17 [measured] and needs no stream at all. That is Amodo's own verifier model.

---

## Environment

| Item | Value |
|---|---|
| Node | Lucid DGX H100 (`h100-sxm-8-0`), Ubuntu 24.04.4, kernel 6.8.0-138 |
| GPU | 1 × NVIDIA H100 80GB HBM3 SXM, 132 SMs, CC 9.0, `CUDA_VISIBLE_DEVICES=0`, PCI `1B:00.0`. Step 0 saw `D1:00.0`; the reservation moved GPUs after a session restart. Same model. |
| Driver / CUDA | 580.173.02 (supports CUDA ≤ 13.0). Toolkit: CUDA 12.6.85, user-local, matching Amodo's Dockerfile. |
| Host compiler / build | gcc 13.3.0, CMake 4.4.4 + Ninja (venv) |
| CPU available to us | 2 logical CPUs (one Xeon Platinum 8480CL core and its hyperthread). All host-side timings are single-core. |
| Amodo | `https://github.com/Amodo-Design/PoSE-Memory-Wiping` @ `fae0935d37a4e2b983334e5b999cbc2c4b6edf67`, unmodified for all baseline results |
| Build flags | `-DCMAKE_BUILD_TYPE=Release` (`-O3 -DNDEBUG`), `POSE_CUDA_ARCH=90`, `POSE_GPU_LABEL_STRATEGY=warp` (also `block`, `level`), `POSE_GPU_WARP_MIN_BLOCKS=3` (also 4). Out-of-tree via `harness/CMakeLists.txt`. |
| Profilers | Nsight Systems 2024.5.1 (CUDA tracing works). **Nsight Compute 2024.3.2 and `nsys --gpu-metrics-devices` fail with `ERR_NVGPUCTRPERM`** (counters restricted to admins). No workaround was attempted. |
| Limits honored | ≤ 60 GiB GPU (enforced by a ballast allocation), ≤ 64 GB host (peak RSS 48.1 GiB), no disk output, no sudo, runs ≤ 4 min |

---

## Part 1: How the code works

### 1.1 Overview

```
 χ  (32-byte session seed from the verifier)
 │
 │  chunk_seed_j = BLAKE3-derive-key("pose-db/chunk-seed", χ ‖ u64be(j))          [host, per chunk]
 ▼
 ┌──────── HOST, once per chunk size m (independent of χ) ─────────────────────────────────────┐
 │ pose_graph_edges(m): node table (≤2 parents each)  →  dependency levels  →  level order     │
 │ → slot map (scratch reuse)  →  rank map (which nodes are outputs, where they go)            │
 │ descriptor = derive-key("pose-db/descriptor", m‖n‖256);  keys K_src, K_int (constants)      │
 │ upload ≈ 0.45–0.73 GB of topology to the GPU                         [2.9–4.1 s, one core]  │
 └─────────────────────────────────────────────────────────────────────────────────────────────┘
 │  H2D: topology once; then 32 B of seed per chunk per batch (~100 KB)
 ▼
 ┌──────── GPU: one warp per chunk, ~3,168 chunks in flight ────────────────────────────────────┐
 │ for level ℓ = 0 … 393,196:                      (__syncwarp between levels)                 │
 │   lanes split the level's nodes v:                                                          │
 │     label[v] = BLAKE3_K( idx_be(v)‖0⁵⁶  |  label[p0]‖label[p1]  |  chunk_seed_j‖desc )      │
 │     scratch[slot[v]] ← label[v]                     (8 MiB per chunk, recycled)             │
 │     if v is an output (rank r): out[j·m·32 + r·32] ← label[v]                               │
 │ scratch zeroed + freed at the end of the call                                               │
 └─────────────────────────────────────────────────────────────────────────────────────────────┘
 │
 ▼
 caller's cudaMalloc buffer:  stored label of global block b at  base + 32·b
 │     (chunk j = b / m, rank r = b % m)
 ├─► stays in HBM                              (library: pose_graph_hbm_topo_label)
 ├─► cudaMemcpy → host DRAM                    (our harness; 55 GB/s if pinned)
 └─► cudaMemcpy → pinned stage → pwrite(O_DIRECT) to raw NVMe   (Amodo's disk-wipe-bench; read, not run)
```

### 1.2 Graph construction

**What it is** [code]. It is the depth-robust DAG of **PoSE-DB** (Bursuc, Gil-Pons, Mauw, Trujillo-Rasua 2024, arXiv:2401.06626), cited in `common/src/graph.c`. It is built recursively from butterfly networks, in the style of a superconcentrator:
- **`emit_connector(d)`:** a butterfly of d+1 layers of width 2^d. Layer k node i hashes nodes i and i XOR 2^k of the previous layer.
- **`emit_connected(L)`:** connected(L−1) → two chained butterflies that merge its output with fresh inputs → connected(L−1).
- **`emit_standalone(L)`:** standalone(L−1) → butterfly → connected(L−1).
- **One chunk's graph:** two disjoint copies of standalone(L), with L = log2(m) (`do_label`, `pose_graph_edges`).

*Why it is built this way:* butterflies give every output a dependency on many inputs. The recursion stacks them so that any large set of nodes still contains long dependency paths (depth robustness). That property is what makes a discarded label slow to regenerate.

**In-degree and parents** [code + measured].
- Nodes have 0, 1 or 2 parents (`emit_source`, `emit1`, `emit2`). Parents are sorted by id.
- Parent choice is **fixed by m alone**: neither seed-derived nor data-dependent. `pose_graph_edges` runs with no seed at all. That is what lets the GPU build the topology once and reuse it for every chunk and every χ.
- Measured at m = 2^17 (`--graph-stats` on Amodo's own `pose_graph_edges`): **2 source nodes** (one per copy), 2,490,366 nodes with one parent, and 33,685,502 with two.

**Size: nodes per byte of output** [measured]. The total is ≈ m·(k² − k + 4) for m = 2^k.

| m | nodes per chunk | nodes per stored label | node hashes per stored byte | depth (levels) |
|---|---|---|---|---|
| 16 | 254 | 15.9 | 0.50 | 42 |
| 4096 (code default) | 557,054 | 136 | 4.3 | 12,274 |
| 16384 | 3,047,422 | 186 | 5.8 | 49,136 |
| **131072 (Amodo's benchmark)** | **36,175,870** | **276** | **8.6** | **393,197** |
| 2^20 (max) | 402,653,182 | 384 | 12 | ≈3.1 M [inferred] |

**Stored or computed on the fly?**
- The CPU path regenerates the graph from the recursive formula for every chunk, with no edge table [code].
- The GPU path materialises it once on the host as arrays: preds, level order, slot map, output ranks. That is 13–21 B per node, uploaded as **456 MiB (`level`) or 730 MiB (`warp`/`block`)** at 2^17 [measured].

**Depth and what it implies.**
- The longest chain is **3m − log2(m) − 2 levels**: 393,197 at 2^17. Stored labels sit at levels 196,607–393,196 [measured].
- Regenerating a discarded label means walking up to about 393k *sequential* hash steps. That is the time-hardness PoSE relies on (Part 3).

### 1.3 Label computation

- **Size: 32 bytes** (`POSE_HASH_BYTES`, `hash.h`) [code]. Not configurable in practice: the message layout, the descriptor (`256` bits) and the GPU code all assume 32.
- **Hash** [code]. Keyed BLAKE3 over a 192-byte, single-chunk message, which is **3 compressions per node**. CPU: `pose_label_node`, `hash.c`. GPU: `pose_gpu::label_node`, `blake3_node.cuh`, with its core adapted from Blaze-3/BLAKE3-gpu.

```
block 0  [  0.. 63]  node index (u64, big-endian, LOCAL to the chunk) ‖ 56 zero bytes
block 1  [ 64..127]  parent-0 label ‖ parent-1 label        (zeros if absent)
block 2  [128..191]  chunk seed     ‖ graph descriptor
```

- **Keys** [code]. Two constants: `"pose-db/label/src"` for the 2 source nodes and `"pose-db/label/int"` for all others.
  - These are BLAKE3's *derive-key context keys* (`ensure_keys`, `hash.c`), not the output of a standard `derive_key(context, material)`.
  - A third-party verifier (for example Python or Rust BLAKE3) must reproduce this detail, or hard-code the two keys.
- **Where χ enters** [code]. Only through the chunk seed in block 2:
  `chunk_seed_j = derive_key("pose-db/chunk-seed", χ ‖ u64be(j))` (`pose_chunk_seed`), with j = global block offset / m.
  - Different chunks share node indices and topology, and differ only through this seed.
  - The descriptor `derive_key("pose-db/descriptor", m‖n‖256)` binds labels to the graph size.
- **Notable consequence** [code + measured]. Block 0 depends only on a constant key and the local node index, never on χ or on the chunk. Its compression is the same for every chunk of every wipe. Amodo recomputes it for every node; precomputing it is improvement #1.

### 1.4 Storage: what is kept and what is discarded

**Kept: only the output set O(G).** That is m labels per chunk, out of about 276·m hashed at 2^17 [code].
- Every other node lives briefly in a recycled scratch slot and is discarded; the scratch is zeroed at the end of the call.
- Amodo's reason (`docs/labeling-explained.md`): PoSE-DB's soundness bound covers *only* O(G). Scaffold nodes are shallow enough to recompute quickly, so challenging them proves nothing.

**Which nodes are outputs** [code + measured].
- The *second* half of each standalone copy's base array (`graph.c`: `do_label`, `pose_graph_edges`). Those are the leaves of the final `connected` block.
- **Each has exactly one parent, a scaffold node.** Amodo's `pose_graph_edges` confirms it: 0 of 131,072 output parents are outputs.
- Amodo's docs (`graph.h` header and `labeling-explained.md` §4) wrongly say the second copy contributes its *first* half.

**Outputs are not sinks** [code, `graph.h` slot-map comment]. Later scaffold nodes read them, so one output's ancestry contains other outputs, but only through long scaffold paths. At m = 4096 an output's ancestor cone holds 121k–279k nodes [computed on a re-implementation of the emitter].

**Not in place.**
- Outputs go to the caller's buffer; scaffold goes to separate scratch.
- The GPU slot map (`pose_graph_slot_map`) frees a slot once the last level that reads it has finished. That gives **8 MiB of scratch per chunk** (pool = 2m slots) [measured].

**Layout** [code + measured]. Chunk j occupies bytes [j·m·32, (j+1)·m·32). Rank r is at offset 32·r (left copy first). Global stored block b lives at `base + 32·b`. A partial trailing chunk is left untouched.

### 1.5 Execution on the GPU

**CPU vs GPU split** [code + measured].
- The host does everything seed-independent: graph, levels, order, slot map, descriptor and keys. That takes 2.9–4.1 s on one core at 2^17, once per process.
- The host also derives a 32-byte seed per chunk.
- The GPU does only the hashing and the output scatter.

**Transfers** [measured, nsys].
- The topology upload is about 470 MB once (~0.07 s). Seeds are about 100 KB per batch.
- **The library makes no device-to-host transfer.** Labels stay where the caller put the buffer.

**Parallelism.** Within a chunk, only nodes on the same level are independent: on average 92 per level, and 49% of levels are narrower than 32 [measured]. Real parallelism comes from **thousands of independent chunks**. Four strategies are compiled in by a CMake flag:

| strategy | one chunk is processed by | barrier between levels | chunks in flight (H100) | scratch | MiB/s at 12.4 GiB [measured] |
|---|---|---|---|---|---|
| `level` (**CMake default**) | all threads, wave of ≤43–64 chunks | `grid.sync()` per level | 43 | 46 GiB (full scaffold per chunk) | **55.5** |
| `block` | a 256-thread block | `__syncthreads()` | 792 | 6.2 GiB | 609 |
| `thread` | one thread, serial | none | (memory-capped) | — | not run |
| **`warp`** | one warp (32 lanes) | `__syncwarp()` | **3,168** (24 warps/SM, 70 regs) | 24.75 GiB | **775** |

**Synchronisation and determinism** [code + measured].
- No floating point. No device atomics. Each node writes its own slot. Parents sit on strictly lower levels behind a barrier.
- Batch sizes and SM counts change scheduling, never hash inputs or output addresses.
- All strategies produced **identical digests**.
- **Scratch sizing** [code]. Scratch is sized from `cudaMemGetInfo` at every call. `level` will take nearly all free HBM: 58 GiB in our runs, until our 60 GiB ballast stopped it.

### 1.6 Verification and output paths (as they exist)

- **No neighbor-check verifier and no challenge protocol** [code, README]. The README says the verifier, the RAM/HBM session code and the boot images are *not* in this repo.
- **`pose_graph_challenge`** (`graph.c`) returns one label by recomputing **the whole chunk graph**: 36.2M hashes and ~1.2 GB of scratch at 2^17 [code].
- **`disk-wipe-bench --verify N`** (`verify_disk`) reads back N *evenly spaced* super-chunks, recomputes each fully on the CPU (`pose_graph_label_region_pooled_inplace`), and compares them with `memcmp` [code]. It is a correctness check, not a timed challenge.
- **GPU self-test.** `pose_gpu_label_node_single` exists but nothing calls it [code]. We used it: 1,400 random nodes, 0 mismatches against the CPU [measured].
- **Disk path** (`tools/disk-wipe-bench/disk_wipe_bench.cu`) [code; read, never run]:
  - one thread per GPU;
  - the topology is built once;
  - per window (default min(30% of free VRAM, 16 GiB)): label in HBM → synchronous `cudaMemcpy` in 1 GiB slices to a pinned stage → `pwrite` with `O_DIRECT` → `fsync` per range;
  - no overlap ("v1");
  - the disk offset equals the stored-label address, so K GPUs over disjoint ranges write exactly what one GPU would.
- **Two cautions about the disk tool** [code]:
  - Even `--dry-run` opens the raw device `O_RDWR|O_EXCL|O_DIRECT`, which is why we never ran it.
  - **The default seed is a fixed public constant ("DiskWipe…").** A real, challengeable wipe needs `--seed-hex`.

---

## Part 2: Performance

### 2.1 Method

- **Harness.** Our own `harness/label_mem.cu` calls only Amodo's public API: `pose_graph_hbm_topo_build`, `pose_graph_hbm_topo_label`, `pose_graph_label_region_pooled_inplace`, `pose_gpu_label_node_single`.
- **Where labels go.** A `cudaMalloc` buffer that stays in HBM, or a host DRAM buffer filled window by window (`--host-gib`, optionally `--pin`). **No change to Amodo's code was needed to keep labels in memory.**
- **Correctness of every run.** BLAKE3 of the whole label buffer, plus CPU recompute of sampled chunks.
- **Repetitions.** 2 per size, which agreed within 3%.
- **Settings.** m = 2^17 throughout; seed S0 = bytes 00..1f.
- **Timing.** Wall clock and CUDA events agree to the millisecond. Throughput is in *stored* bytes, the convention Amodo uses.

### 2.2 Results

**Labels resident in HBM (`warp`)** [measured]:

| stored labels | chunks | batches (×3,168) | time | GB/s | MiB/s | labels/s | node hashes/s | stored-bytes / HBM peak |
|---|---|---|---|---|---|---|---|---|
| 1 GiB | 256 | 0.08 | 7.64 s | 0.14 | 134 | 4.4 M | 1.2 G | 0.004% |
| 4 GiB | 1,024 | 0.32 | 7.9–8.1 s | 0.54 | 513 | 16.8 M | 4.6 G | 0.016% |
| **12.4 GiB** | 3,168 | 1.00 | **16.3–16.4 s** | **0.81** | **774** | **25.4 M** | **7.0 G** | **0.024%** |
| 16 GiB | 4,096 | 1.29 | 24.1–24.2 s | 0.71 | 678 | 22.2 M | 6.1 G | 0.021% |
| 32 GiB | 8,192 | 2.59 | 44.7–44.8 s | 0.77 | 732 | 24.0 M | 6.6 G | 0.023% |

**Host DRAM, 48 GiB, via 12.4 GiB GPU windows** [measured]:

| | total | labeling | copy to host | MiB/s |
|---|---|---|---|---|
| pageable `malloc` | 77.4 s | 65.5 s | 11.9 s (4.3 GB/s) | 635 |
| **pinned** (`cudaHostRegister`, 2.1 s one-off) | **66.4 s** | 65.4 s | **0.93 s (55 GB/s)** | **741** |

- Both runs gave the same digest. Peak RSS was 48.1 GiB.
- Touching 48 GiB of fresh 4 KB pages took a further 19.6 s on our one core.

**"Fraction of peak bandwidth" needs care.**
- In stored bytes it is 0.024% of 3.35 TB/s. That number is meaningless because of the scaffold.
- In estimated real memory traffic it is **about 20%**. Each node reads 2 parent labels and writes 1 label in scratch, about 96 B per node × 7.0 G nodes/s ≈ 0.67 TB/s [inferred; counters blocked].
- For scale, Amodo's own `cudaMemset` of 26.6 GB of scratch ran at **3.27 TB/s**, 97% of peak [measured, nsys]. A plain zero-fill of HBM is about 4,000× faster than labeling.

### 2.3 Where the time goes

From the nsys timeline of one 12.4 GiB `warp` call [measured]:

| phase | time | share |
|---|---|---|
| Topology build on the host (one core) | 3.4–4.0 s | one-off per process and m |
| Topology upload (470 MB, pageable) | 0.07 s | — |
| **`k_label_chunk_warp`, one launch** | **16.37 s** | **~96%** of steady-state time |
| Seed uploads | ~5 µs per batch | ~0 |
| Scratch zeroing (26.6 GB `cudaMemset`) | 8 ms | ~0 |
| Device→host copies (host fill only) | 3.1% pinned, 15% pageable | |

### 2.4 Bottleneck analysis

**The kernel's machine code** [measured with `cuobjdump`]. 2,584 SASS instructions, almost all BLAKE3 arithmetic: 700 `LOP3` (xor), 692 `SHF` (rotate), 461 `IMAD` and 253 `IADD3` (add), 99 `PRMT`. Memory: 187 loads and 68 stores, including byte-wise fallback paths that don't run. 70 registers per thread caps occupancy at 3 blocks, i.e. **24 warps per SM** — hence 3,168 chunks in flight.

**Integer-ALU utilisation** [inferred].
- A warp handles one node per lane per "round". At 2^17 a chunk needs 1,284,825 rounds for 36.2M nodes, so **lane efficiency is 0.88** [measured from topology]. Half of all levels are narrower than 32.
- A full batch is 24 chunks per SM × 1.285M rounds in 16.34 s, about 1,050 SM cycles per warp-round at 1.98 GHz.
- The hash needs about 1,650 instructions on the integer pipe. At 64 lanes per clock per SM, that is about 825 cycles per warp-round.
- So the integer pipe is **about 79% busy** (about 69% useful after idle lanes).

**Memory.**
- About 20% of HBM peak (above). Scratch (25 GiB) far exceeds L2 (50 MB). The topology (0.73 GB) is shared by all warps marching through levels roughly in step, so it largely hits L2 [inferred].

**The experiments support "compute-bound"** [measured]:
- 33% more warps in flight (`MIN_BLOCKS=4`) gained only 4.5%.
- Removing 1 of 3 compressions gained 18–19%.
- Neither would hold for a bandwidth-bound kernel. The block-0 gain falling short of the ideal 1.5× shows that non-hash per-node work (gathering parents, topology loads, idle lanes) is also significant.

**Two regimes.**
- **Saturated, ≥ 3,168 chunks:** limited by integer arithmetic.
- **Small, < 3,168 chunks:** **latency-bound**. A batch takes about 8 s even when nearly empty, because each warp must walk 393k dependent levels.
- Hence throughput depends on how full the batches are (16 GiB windows lose 12%).

**How throughput varies:**
- *With total size:* flat once windows are full batches. Sawtooth otherwise (table above).
- *With label size:* not applicable, since labels are fixed at 32 B.
- *With chunk size m:* hashes per stored label are 136 / 186 / 276 / 384 at m = 2^12 / 2^14 / 2^17 / 2^20. So throughput should scale about inversely [inferred; only 2^17 was timed at scale].

**Comparison with Amodo's own numbers.**
- Their H100 `block` figure of 179 MiB/s is far below our 609. We suspect it predates their vectorised I/O change, but can't confirm.
- Their H200 `warp` figure of 620 MiB/s is below our H100's 775.
- Their profiling of `block` (barrier-bound, 5% HBM) is consistent with ours once the barrier is removed (`warp`), leaving the hash.

### 2.5 Extrapolations

At the measured 0.81 GB/s per H100. Disk speed is ignored, as asked.

| target | estimate | reference (`docs/context.md`) |
|---|---|---|
| 80 GB of H100 HBM | ~99 s of labeling at full rate. In practice HBM can't hold its own labels *and* `warp`'s 25 GiB scratch plus 0.7 GiB topology. Fill ~54 GiB, then a second pass over the scratch region with a small-scratch strategy: ~2–2.5 min [inferred] | — |
| 190 GiB HBM (Rubin-class GPU) | ~4.2 min at H100 rate | 8.6 min |
| 490 GiB host DRAM, one GPU | 10.8 min (labeling-limited); 11.3 min end to end pinned; 13.2 min pageable | 6.7 min |
| **15.36 TB disk, one GPU** | **5.3 h** | **~5 h** |
| NVL72 rack memory (20.7 TB HBM + 54 TB LPDDR5X) over 72 GPUs | ~21 min at H100 rate, ~18 min with improvement #1 [inferred; Rubin GPUs should be faster] | — |

- **The disk reference (~5 h) matches one GPU's labeling rate almost exactly.** That suggests the reference itself was label-bound, not disk-bound [inferred].
- **The HBM reference (8.6 min for 190 GiB ≈ 0.40 GB/s) is half our H100 rate.** The DRAM reference (≈ 1.3 GB/s) is above it.
- We don't know the m, GPU count or code version behind those figures. Zach should ask Amodo before relying on either comparison.

### 2.6 Improvement ideas, ranked

| # | idea | expected gain | evidence | effort / risk |
|---|---|---|---|---|
| 1 | **Precompute block 0's chaining value per node** (χ-independent; a 32 B × nodes table, built on the GPU in ms) | **+18–19% [measured]** | prototype branch `study/block0-precompute`: 775 → 914–926 MiB/s at 12.4 GiB, +37% at 1 GiB, identical digests | low (~60 lines, nothing protocol-visible); +1.1 GB GPU memory at 2^17; also applies to `block` and CPU paths |
| 2 | **Pinned host memory** for DRAM and disk fills | **+17% end to end [measured]** | copies 4.3 → 55 GB/s; 48 GiB host fill 635 → 741 MiB/s | trivial. WipeOS can register its 1 GB huge pages once (D22). Overlapping copies with labeling adds ≤ 1.5% on top. |
| 3 | **Eliminate the tail batch:** size windows to multiples of the resident-warp count, or a persistent kernel pulling chunks from a counter | 5–14% at typical window sizes | 16 GiB: 678 vs 775; 32 GiB: 732 vs 775; batch time ~16 s full vs ~8 s nearly empty | free (sizing) or moderate (persistent kernel; output stays deterministic, since the counter only assigns work) |
| 4 | **Pack narrow levels:** two chunks per warp on levels < 32 wide, or re-order levels across subgraphs | up to ~12% [inferred] | lane efficiency 0.88; 49% of levels < 32 wide | moderate; schedule-only, no protocol change |
| 5 | `MIN_BLOCKS=4` (Amodo's knob; 62 regs, 32 warps/SM) | +4.5% [measured] | 775 → 810 MiB/s at a full 4,224-chunk batch | zero code; +8 GiB scratch (bad for HBM self-wipe, fine for DRAM/disk) |
| 6 | **Ship or cache the topology** (seed-independent) instead of building it at boot | 3–4 s per process | nsys: single-core host build | low; matters for short runs and weak boot CPUs |
| 7 | *Policy:* choose m | proportional to 276 → 186 (m = 2^14, 1.5×) | node counts above | security trade: depth, and so cheater recompute time, falls ~8× |

- **Combined:** #1 + #3 + #5 might reach about 0.95–1.0 GB/s per H100 [inferred, untested].
- **Not promising:** layout or coalescing work aimed at HBM bandwidth, which is only about 20% used.

---

## Part 3: What matters for WipeOS

### 3.1 The neighborhood check (KR2.2): it does not work on this graph as it stands

**The fact** [measured on Amodo's `pose_graph_edges`, m = 16 … 2^17].
- **Every stored label has in-degree 1, and its single parent is a scaffold node.** Across all four sizes, 0 of the output-node parents are outputs.
- The honest node never stores that parent. It is overwritten in a recycled scratch slot within a few levels and zeroed at the end.

**Consequences for candidate C (D18)** [inferred, argued from the structure].

1. **An honest node cannot answer a neighborhood query.**
   - The check is "label = H_χ(parents)", with the node returning the queried label *and its parents*.
   - The node doesn't have the parents.
   - Recomputing them means recomputing the chunk, which takes 1.7–1.9 s, the very cost the deadline is meant to make prohibitive.

2. **Streaming or storing the immediate parent doesn't close the gap.** The neighborhood check exists to stop a node streaming cheap, regenerable fake values.
   - A cheater can choose a fake parent p = PRG(k, i), compute its "label" ℓ = H(idx, p, chunk_seed, desc) in a single hash, and stream fingerprints of both.
   - At query time it regenerates p and ℓ in microseconds. The pair is locally consistent and passes.
   - A one-hop check only binds a value when the parent is *itself* bound: either stored-and-checked, or checked against its own parents, recursively down to the two source nodes.
   - In this graph that recursion runs through the whole scaffold.

3. **Binding everything is prohibitively expensive.**
   - Checking a hash relation needs *full* 32-byte values, not 16-byte fingerprints. The server can't recompute H from fingerprints.
   - Spot-checking edges therefore means the node must stream (or keep available) values for essentially every node: 276 nodes per stored label at 2^17. That is **~276 bytes of stream per byte stored** (~138 B/B even with 16-byte fingerprints, which cannot actually be checked).
   - For one 80 GB GPU that is about 22 TB of stream; for an NVL72 rack's ~75 TB of memory, about 20 PB.

4. **D18 also assumed 4 KB labels; these are 32 B.** Even the cheap part of C, a 16-byte fingerprint of each *stored* label, would be a stream half the size of the memory being wiped. That is about 37 TB for an NVL72 rack, or 0.4 GB/s per GPU at our fill rate.

**Ways forward** [inferred; for Zach to evaluate].

- **(A) Recommended: drop the stream and let the server recompute a secret sample, ahead of time.** This is Amodo's own model. The `gpu_label.h` comments say the HBM labels are "byte-identical to the CPU path … so the verifier can challenge it with the same common/graph.c FFI".
  - **Server cost.** The server knows χ, so it can pick its secret sample positions *before* the fill and compute the expected labels **while the node is filling**. That keeps the work off the response path.
  - **Per-sample cost.** One chunk recompute is **1.7 s on one CPU core** at m = 2^17 [measured]. About 26 ms at m = 4096 [inferred, scaled by node count].
  - **Possible reduction.** Recomputing only the queried output's ancestor cone instead of both copies would cut this by roughly 2–3× [inferred; not implemented].
  - **Total.** 1,000 samples at 2^17 is about 28 core-minutes. A modest multi-core server overlaps that with a ~10-minute fill.
  - **Scaling.** Server cost grows with the *number of samples*, not with memory size. **This may make D16's concern much smaller than assumed.** Whether a sample of this size gives the soundness Pod-PoComp needs is a separate PoSE-DB calculation.
- **(B) Change the graph so that stored labels' parents are stored labels.** Classic PoSE with every node stored, e.g. on a depth-robust graph. Then a neighborhood check works.
  - But the PoSE-DB soundness argument, which covers only its output set, no longer applies. Shallow stored nodes are fast to recompute.
  - This is a new cryptographic design, not a code change.
- **(C) Group labels.** For example, one fingerprint per 4 KB of consecutive stored labels (16 B per 128 labels, 0.4% stream).
  - This fixes the stream size.
  - **But it doesn't** solve the binding problem in point 2 above unless it is combined with (A) or (B).

### 3.2 Fingerprints: where they would be cheapest

- **Where** [code]. If WipeOS still wants per-label fingerprints, for example with (C), the cheapest place is the `warp` kernel's output branch, right after the label is computed: `label_gpu_warp.cu`, the `if (r >= 0) copy_label(...)` line. The label is still in registers there.
- **Cost of a 16-byte fingerprint** (one extra single-block BLAKE3 compression over label ‖ chunk ‖ rank):
  - per stored label, 1 compression against 276 × 3 = 828 already spent, **about 0.1% extra compute** [inferred];
  - plus writing it to a parallel array (16 B per 32 B label) and streaming it off the GPU.
- **A 4 KB group fingerprint** would be cheaper still to stream. It needs the 128 labels of a group to be combined, which they are not naturally in one warp, since ranks are scattered across levels.

### 3.3 Recomputation cost (the response-deadline bound)

| who / how | time to regenerate one 2^17 chunk |
|---|---|
| H100, Amodo `block` or `level`, one chunk alone | **1.90 s** [measured] |
| H100, Amodo `warp`, one chunk alone | 4.95 s; 3.94 s with block-0 precompute [measured] |
| One Sapphire Rapids core, Amodo CPU path (AVX-512 BLAKE3) | **1.70 s** [measured] |
| A latency-optimised cheater: critical path 393k levels × **2** dependent compressions (block 0 is off the critical path) at ~100–250 ns each | **~0.1–0.3 s** [inferred, not measured] |

- **Answering from memory takes microseconds plus the network round trip.** A response deadline in the low tens of milliseconds therefore leaves a wide margin at m = 2^17.
- **At m = 2^14 the depth is 8× smaller,** so an optimised cheater's time falls toward ~10–40 ms and the margin gets thin.
- **The deadline and m have to be chosen together.**
- Getting a solid lower bound would need a purpose-built latency kernel. That is a good item for Zach's kernel project.

### 3.4 Verifier cost on a weak CPU-only server

| check | cost |
|---|---|
| One label from its parents (if parents were available) | 3 BLAKE3 compressions, well under 1 µs on one core [inferred] |
| One label from scratch at m = 2^17 (Amodo's model) | **1.7 s, one core** [measured], ~40 MiB of scratch (in-place path) |
| Same at m = 4096 | ~26 ms [inferred by scaling] |

Since (A) lets the server precompute during the fill, the real constraint is total core-seconds (samples × per-sample cost), not latency.

### 3.5 Determinism

**Verified bitwise identical** [measured] across all of these:
- two runs in one process, and runs in separate processes;
- `warp` vs `level` vs `block`;
- `MIN_BLOCKS` 3 vs 4;
- the block-0 prototype vs main;
- one call vs two windows with offsets;
- 1 GiB, 2 GiB, 12.4 GiB and 48 GiB host fills;
- GPU vs CPU, with 27 full chunks recomputed in total and 1,400 single nodes.

A one-bit change in χ changes the output completely.

**What could break it** [code + inferred]:
- **Unlikely:** none of the usual suspects (floating point, device atomics, reduction order) are used.
- **Real risks:**
  1. **`chunk_blocks` and `region_block_offset`** are part of the label's identity. WipeOS must fix them per layout (D24).
  2. **Seed derivation for χ shorter or longer than 32 B** — `pose_chunk_seed` accepts any length, so χ must be canonicalised.
  3. **Future code changes to topology order** — the slot map and level order are schedule-only, but node ids are hash inputs, so a different emitter changes labels.
- **Not tested:** other GPU models or SM counts. By construction they should not matter.

### 3.6 Filling HBM and DRAM, not just disk

- **Host DRAM: yes, today.**
  - Label a GPU window, then copy it into the host region at the matching `region_block_offset`.
  - We measured 741 MiB/s end to end with pinned memory, and the result was byte-identical to an all-GPU run.
  - **WipeOS needs:** a global layout mapping every byte (HBM, DRAM, later disk) to a global block index; pinned or registered huge pages (D22); and one worker per GPU. The label depends only on (χ, chunk index), so any GPU can fill any range.
- **HBM itself: yes, with caveats.** `pose_graph_label_hbm` labels a device buffer in place. But the call itself needs non-wiped GPU memory, which must be wiped separately:
  - topology: 0.45–1.9 GB;
  - scratch: 24.75 GiB for `warp`, 6.2 GiB for `block`, about 46 GiB or "all of it" for `level`.

  A practical HBM wipe is two passes: `warp` over most of HBM, then a small-scratch pass, or a fill from a neighbour GPU or the host, over the region that held the scratch.
  - Amodo's README flags the same issue ("unattested space and needs a separate pass").
  - On scratch zeroing: Amodo zeroes scratch on success. On the error path (`goto cleanup`) it frees without zeroing [code]. That doesn't matter for security, since the wipe failed, but is worth knowing.
- **The missing pieces in Amodo's repo are exactly WipeOS's:** RAM and HBM session code, layout, challenge and response, and the verifier [README].

### 3.7 Dependencies (D27)

**Build time** [measured]:
- `nvcc` (CUDA ≥ 11.5; we used 12.6);
- CUDA headers including `cooperative_groups.h` (header-only);
- the static cudart (`libcudart_static.a`);
- CMake ≥ 3.18, a C11 and C++17 compiler, pthreads.

No cuBLAS or any other CUDA library.

**Run time** [measured with `ldd`]: the binary needs only `libc`, `libm`, `libstdc++` and `libgcc_s`. **cudart is linked statically** (CMake's default).
- It still needs **`libcuda.so.1`** (the driver library) at run time. The static cudart `dlopen`s it (standard CUDA behaviour; the run succeeded, but we did not trace the load).
- It also needs the kernel modules (`nvidia`, `nvidia-uvm`) and device nodes.
- **No driver-API (`cu*`) calls** are made directly [code].

**So:** the GPU worker can be a small dynamically linked binary (glibc + libstdc++), with everything CUDA-specific except `libcuda` linked in. A fully static binary isn't possible, because `libcuda` is shared-only and `dlopen` from static glibc is not reliable. This confirms D27's separate dynamically linked GPU worker.

### 3.8 Portability (D17)

- **GPU** [code]. Nothing Hopper-specific: no TMA, clusters or `cp.async`. Only `__byte_perm`, funnel shifts and `uint4` loads, all available on every recent GPU.
  - The build emits **native SASS only** for `POSE_CUDA_ARCH` (default 90; `100` is mentioned for Blackwell).
  - **Rubin needs a rebuild with its arch value.** Consider adding PTX (e.g. `90-virtual`) for forward compatibility.
  - The resident-warp count, and so the best window size, will differ on Rubin. Size windows at run time (improvement #3).
- **CPU** [code].
  - x86-specific: BLAKE3 SSE/AVX2/AVX-512 backends with CPUID dispatch, and AES-NI for the unused AES-PRF hash.
  - **Arm:** NEON BLAKE3 and armv8 crypto are already supported. Arm appears to be Amodo's primary CPU target.
  - Linux-only pieces (`O_DIRECT`, `BLKGETSIZE64`) are in the disk tool only.
  - The single-threaded topology build (3–4 s on x86) should be timed on Vera, or shipped prebuilt (#6).

### 3.9 License

- **MIT**, © 2026 Amodo Design Ltd. Vendored BLAKE3 1.8.5 is CC0 / Apache-2.0. The GPU BLAKE3 core derives from Blaze-3/BLAKE3-gpu (MIT).
- **WipeOS can reuse and modify it** with the copyright and permission notices retained.
- `NOTICE`: the code is unaudited research code, and the licence does not grant use of Amodo's name or branding.

### 3.10 Anything else

- **The graph has only 2 source nodes per chunk** [measured]. Every label derives from H(source) under the chunk seed: fine cryptographically, but worth knowing.
- **Node indices are local to a chunk**, so all chunks share the topology and differ only through `chunk_seed`. That is what makes the one-off topology build possible.
- **Choose the strategy deliberately.** The CMake default `level` is about 14× slower than `warp` and grabs nearly all free HBM.
- **`--verify` samples evenly spaced chunks deterministically.** That is fine for a correctness check, not as a proof.
- **Stale or contradictory docs** [code]:
  - which half of the second copy is stored;
  - "≈17 MB scratch per thread", which applies to the old non-in-place path, not the current ~40 MiB;
  - "x86 SIMD disabled" in `docs/common-library.md`;
  - H100 `block` = 179 MiB/s.

---

## Open questions and surprises

1. **Candidate C is incompatible with Amodo's graph** (Part 3.1). This is the main contradiction with our assumptions in `docs/context.md`.
   - **Zach should check** the binding argument in point 2 of 3.1, and whether option (A) (server pre-computes a sample) satisfies D16's intent.
2. **Labels are 32 B, not 4 KB.** Any fingerprint-per-label design is 50% stream.
3. **The reference timings don't line up with ours.**
   - The disk figure matches one GPU's labeling rate.
   - The HBM figure is half our rate.
   - The DRAM figure is faster than one GPU at our rate.
   - Ask Amodo which m, GPU count and code version produced them.
4. **The fastest version in the repo is about 4,000× slower than a plain HBM zero-fill**, and the cost is entirely scaffold hashing. The time-hardness that makes PoSE sound is the same thing that makes it slow. m is the dial.
5. **Not measured here:**
   - hardware counters (blocked; the compute-bound conclusion rests on SASS and timing arithmetic);
   - other values of m at scale;
   - huge-page first-touch and pinning (needs root);
   - Rubin or Arm;
   - a latency-optimised cheater kernel;
   - ancestor-cone-only verification.
6. **The disk tool's public default seed** means any wipe run without `--seed-hex` is not a proof of anything.

---

## Appendix

### A. Commands

All runs used `source env.sh` and `CUDA_VISIBLE_DEVICES=0`. S0 = `000102…1e1f`; S1 = S0 with the low bit of byte 0 flipped.

**Build** (Amodo unmodified, out of tree):
```
cmake -S harness -B build/<s> -G Ninja -DCMAKE_BUILD_TYPE=Release -DPOSE_GPU_LABEL_STRATEGY=<s>     # s = warp, level, block
cmake -S harness -B build/warp-mb4 ... -DPOSE_GPU_LABEL_STRATEGY=warp -DPOSE_GPU_WARP_MIN_BLOCKS=4
cmake --build build/<s>
(cd build/warp/amodo_common && ctest)                                      # 5/5 pass
ldd build/warp/label_mem
cuobjdump -sass build/warp/label_mem;  cuobjdump -res-usage build/warp/label_mem
```

**Graph statistics** (host only):
```
build/warp/label_mem --cb {16,4096,16384,131072} --graph-stats
```

**Correctness** (Step 3; m = 2^17, 1 GiB):
```
build/warp/label_mem --mib 1024 --seed-hex S0 --reps 2          # and again in a new process
build/warp/label_mem --mib 1024 --seed-hex S1
build/level/label_mem --mib 1024 --seed-hex S0
build/warp/label_mem --mib 1024 --seed-hex S0 --split 2
build/warp/label_mem --mib 1024 --seed-hex S0 --kat 1000 --cpu-check 4
build/warp/label_mem --mib 1024 --seed-hex S0 --d2h
```

**Performance** (Steps 4–5):
```
build/warp/label_mem --mib {1024,4096,12672,16384,32768} --seed-hex S0 --reps 2
build/{block,level}/label_mem --mib 12672 --seed-hex S0
nsys profile --trace=cuda,osrt -o warp12g build/warp/label_mem --mib 12672 --seed-hex S0
build/warp/label_mem --mib 12672 --host-gib 48 --seed-hex S0 --cpu-check 4 [--pin]
build/{warp,block,level}/label_mem --mib 4 --seed-hex S0                   # single-chunk latency ×3
taskset -c 1 build/warp/label_mem --mib 4 --seed-hex S0 --cpu-check 1      # CPU latency ×3
build/warp-mb4/label_mem --mib {16896,12672} --seed-hex S0 --reps 2
build/warp-b0/label_mem --mib 12672 --seed-hex S0 --reps 2 --cpu-check 3   # block-0 prototype
```

### B. Changes and patches

From `notes/changes.md`:
- **Amodo baseline:** `fae0935`, unmodified for every baseline result. The checkout is on `main` and clean.
- **`harness/`:** our own code, not Amodo's.
  - `CMakeLists.txt` builds Amodo's `common/` out of tree.
  - `label_mem.cu` is the in-memory harness: ballast GPU cap, windows, host fill with preflight memory check, pinning, digests, CPU check, KAT, graph stats.
- **`study/block0-precompute`:** a local branch in `PoSE-Memory-Wiping/`, never pushed; also `patches/0001-block0-precompute.patch`.
  - It precomputes each node's seed-independent block-0 chaining value on the GPU and starts the `warp` kernel from it.
  - Reason: Step 5 experiment (b), testing the compute-bound hypothesis.
  - Verified byte-identical to main.

### C. Raw outputs (`runs/`)

| directory | contents |
|---|---|
| `20261021-194157-inventory/` | environment at Step 0 |
| `20261021-201323-step2-graph/` | graph stats, GPU smoke test, build environment and `ldd` |
| `20261021-201903-step3-correctness/` | determinism, seed, strategy, split, KAT, CPU check, D2H |
| `20261021-202528-step4-hostfill-smoke/`, `…-203104-step4-hostfill48/` | host-DRAM fill (pageable) |
| `20261021-202616-step4-sweep/` | warp size sweep, level-width stats |
| `20261021-203319-step4-strategies/` | block vs level |
| `20261021-203754-step4-nsys/` | `warp12g.nsys-rep` and summary CSVs |
| `20261021-203848-step4-latency/` | single-chunk GPU and CPU latency |
| `20261021-204841-step5a-minblocks4/`, `…-205042-step5c-pinned/`, `…-205410-step5b-block0/` | improvement experiments |

Working notes per step are in `notes/00-inventory.md` … `notes/05-improvements.md`. `step1-findings.md` is the earlier shareable code walkthrough; this report supersedes it.
