# Research notes: label verification

**Update, 2026-10-21:** candidate C (D18) has been superseded. Labels are now verified with precomputed secret challenges (D32); see "Revisited after the Amodo study" at the end.

Background research behind D18 (see `context/decisions/`). Not loaded into Claude Code sessions automatically; read it when a task touches label generation, fingerprints or the verifier.

D16 requires that the challenge server knows the correct responses without recomputing labels. Candidate C, streamed fingerprints, is adopted (D18). It keeps B's secret sampling but streams a short hash of each label instead of the label itself, which cuts bandwidth by about 256x.

**Candidate approaches.**

| Candidate | How the server knows the answers | Server cost | Node cost | Main concern |
| --- | --- | --- | --- | --- |
| A. Merkle commitment | The node sends a Merkle root at FILLED, then opens each queried label and its parents with Merkle paths | One label hash plus path checks per sample | Building and storing the tree | Proof-of-space constructions need O(m log m) memory, which leaves part of memory unproven (Bursuc et al.) |
| B. Streamed labels, secret sampling | The node streams every label to the server as it is computed. The server secretly keeps a small random subset, with each kept label's parents, and drops the rest. Queries come only from the kept subset, so the node must store every label. | Line-rate ingest, storing a small fraction of the labels, and one hash per consistency check | Egress equal to the full memory being wiped | Bandwidth; labels must be checked for correctness, not just recorded; parents may be internal graph nodes that are not stored |
| C. Streamed fingerprints, secret sampling (adopted, D18) | The node streams a 16 B hash of each 4 KB label as it is computed. The server secretly keeps a random subset of fingerprints, in neighborhoods, and drops the rest. A query asks for full labels, which the server hashes and compares. | Ingest of about 290 GB for 75 TB of volatile memory; one or two hashes per query | One extra hash per label | Label size trades stream size against the granularity of the security bound; prior art not yet checked |

**Candidate B in more detail.**

- **Correctness check.** Recording labels is not enough. A node could stream values derived from a short secret key, store only the key, and regenerate any value on demand. So for a few kept labels, the server checks that each equals the χ-keyed hash of its kept parents. To pass, a node has to stream a locally consistent labelling almost everywhere, which means computing the real one.
- **No tree needed.** The streamed transcript acts as the commitment: the server holds it before any query is sent. This avoids candidate A's extra memory on the node.
- **Bandwidth.** The node's egress equals the memory it wipes, about 2.8 TB of DRAM and HBM on the DGX test node. At 100 Gb/s that is roughly 4 to 5 minutes; at 400 Gb/s, about 1 minute. The server can drop most packets without reading them.
- **Pod-PoComp accounting.** The label stream is large egress during the erasure window. It must end at the auditor-side server and never be forwarded, and it must be exempt from Y or charged under its own rule.

**Candidate C in more detail.**

- **Principle.** Any shortcut the server uses to check an answer, the node can use to fake one. So the server's check must be a lookup of something the node cannot cheaply regenerate. A fingerprint cannot be inverted, so the only way to return the full label is to have stored it.
- **Correctness check.** The server queries a label together with its parents, checks each against its fingerprint, and checks one χ-keyed hash for consistency.
- **Batching.** Fingerprints are sent in large batches so per-packet overhead stays small.
- **Compartment size.** Changing T_erase does not reduce one event's volume, and splitting a pod conflicts with D8. Staggering different pods' events, or a challenge server per rack, reduces the total load on the taps. Excluding the cache NVMe remains the biggest lever on volume.

Stream time for a Vera Rubin NVL72, which has 20.7 TB of HBM4 and 54 TB of LPDDR5X ([NVIDIA](https://www.nvidia.com/en-in/data-center/vera-rubin-nvl72/)). Each node's north-south link runs through one BlueField-4, at roughly 800 Gb/s ([source](https://hashrateindex.com/blog/nvidia-vera-rubin-nvl72-specs-breakdown/); sources vary), so the challenge server's ingest is the limit:

| Challenge server ingest | All labels (75 TB) | 16 B fingerprints of 4 KB labels (about 290 GB) |
| --- | --- | --- |
| 100 Gb/s | about 100 min | about 23 s |
| 400 Gb/s | about 25 min | about 6 s |
| 800 Gb/s | about 12.5 min | about 3 s |

**Rejected: streaming one in N labels.** The node knows which labels it streamed, so it could store only those and still pass. Letting the server check the unstreamed labels by recomputing them from streamed neighbors fails too, because the node can recompute them faster than the server.

**Literature.**

| Construction | Verifier cost per sample | Security rests on | Notes |
| --- | --- | --- | --- |
| [Bursuc et al. 2024](https://arxiv.org/abs/2401.06626), graph protocol | Recomputes the challenged label from the seed, which can mean many ancestor labels in a depth-robust graph | Round-trip timing (distant attacker), not prover isolation | Fill first, then rapid single-label challenge rounds. In-place depth-robust graph. Built for IoT devices with a stronger verifier; prototype erased 32 KB. Python and C prototype available. |
| [Bursuc et al. 2024](https://arxiv.org/abs/2401.06626), unconditional protocol | Looks up a stored block; no computation | Round-trip timing, no cryptographic assumption | The verifier generates, sends and keeps the entire fill, so communication equals memory size. |

## Revisited after the Amodo study (2026-10-21)

Candidate C was adopted before we had read Amodo's code. The study (`docs/research/amodo-study.md`, §3.1) found that it does not work on the graph Amodo implements, PoSE-DB. Precomputed secret challenges replace it (D32, which supersedes D18).

**Why candidate C fails on PoSE-DB.**

- **No stored label has a stored parent.** Each chunk hashes about 276 nodes for every label it keeps (m = 2^17). Every stored label has exactly one parent, and that parent is a scaffold node that is computed and discarded: 0 of 131,072 output parents are outputs, measured on Amodo's own topology code. An honest node can't answer a neighborhood query without recomputing the whole chunk.
- **Streaming the parents doesn't bind anything.** A one-hop check only binds a label if its parent is bound too, and in PoSE-DB that recursion runs through the whole scaffold. A cheater can stream a fake parent from a PRG and a label hashed from it, then regenerate both on demand. Binding the scaffold would cost about 138–276 bytes of stream per byte stored.
- **Labels are 32 B, not 4 KB.** Even a 16 B fingerprint per stored label is a stream half the size of memory: about 37 TB for an NVL72 rack, not the 290 GB estimated above.

**Options weighed.**

| Option | How answers are checked | Main cost | Main concern |
| --- | --- | --- | --- |
| Live recompute | The challenge server knows χ, picks secret positions and recomputes those chunks while the nodes fill | About 1.7 CPU-seconds per sampled chunk at m = 2^17; about 1,300 sampled chunks per tray on 32 cores in the fill window | Limited by the window; scales poorly with 18 nodes in parallel and gets worse as GPUs get faster |
| Precomputed database (adopted, D32) | Before the event, the auditor precomputes single-use entries offline: a secret χ, secret positions, and a hash of each expected answer. At the event, checking is a lookup | Offline compute and storage per event; a first estimate is about 30 min of one H100 and 0.6 GB per rack event | χ and the positions must stay secret; entries are single-use and tied to the manifest's memory layout; the Pod-PoComp authors must accept a pre-generated χ |
| Deferred verification | The server records the answers and checks them after the event | No secret database | Cheating is detected hours later |
| Commit-and-check proofs of space | The node commits to all its labels with a Merkle root at FILLED and opens each challenged label with its parents; the server checks the paths and one hash relation | Constant work per check, no recomputation | Needs a graph whose stored labels have stored parents, unlike PoSE-DB; the Merkle tree and any unproven fraction of memory add to the unwipeable footprint |

**Outcome.** Precomputation is adopted (D32). It is the simplest to stand up, reuses Amodo's code unchanged, and makes event-time verification a lookup. Commit-and-check is recorded as the deferred successor, and the database's size is the open question "Precomputation parameters" (both in `context/questions/`).
