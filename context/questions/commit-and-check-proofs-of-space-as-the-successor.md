---
title: "Commit-and-check proofs of space as the successor to precomputation"
status: deferred
---

# Commit-and-check proofs of space as the successor to precomputation

A future direction is to remove precomputation's dependence on a secret database (D32).
- How it works: the node commits to all its labels with a Merkle root at FILLED. For each challenged label, it opens the label and its parents with Merkle paths. The server checks the paths and one local hash relation, which is constant work per check with no recomputation.
- What it needs: a graph whose stored labels have stored parents, unlike PoSE-DB. Examples are stacked depth-robust graphs or stacked expanders (Ren and Devadas 2016), and tight proofs of space (Fisch 2019).
- When it would win: it would be the superior solution if node fill speed is comparable to PoSE-DB's (about 0.8 GB/s per H100), and the added unwipeable footprint (the Merkle tree, and any unproven fraction of memory) is acceptably small.
- Status: not a priority while precomputation is good enough.
