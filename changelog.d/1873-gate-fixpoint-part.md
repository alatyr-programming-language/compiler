- **The GitHub gate runs FIXPOINT once, as a part of its own (#1873).** It ran at the head of each of
  the four parts, 38-59 minutes apiece, though no part reads what it builds: each builds its own
  Stage1 from the seed. It is now a fifth parallel part, so the gate's critical path no longer adds
  FIXPOINT to the slowest part, and a FIXPOINT red is named `fixpoint` in one part instead of
  `before-parts` in all four. The serial `scripts/full.sh` is unchanged.
