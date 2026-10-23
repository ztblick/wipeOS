---
title: "Precomputation parameters (D32)"
status: open
group: design
---

# Precomputation parameters (D32)

How many chunks per tray are sampled, and how many labels per chunk? How much database storage and offline compute does each event need? A rough first estimate: about 20,000 chunks per tray and 100 labels per chunk is about 30 minutes of one H100 and about 0.6 GB per rack event. And do the Pod-PoComp authors accept a pre-generated secret χ, given that the paper's validity condition says χ is "generated after the ordinary-traffic cut-off"?
