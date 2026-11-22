- **The GitHub gate runs FIXPOINT once, as a part of its own (#1873).** It ran at the head of each of
  the four parts, 38-59 minutes apiece, though the other parts build their own Stage1 from the seed.
  It is now a fifth parallel part, so the gate's critical path no longer adds FIXPOINT to the slowest
  part, and a FIXPOINT red is named `fixpoint` in one part instead of `before-parts` in all four. The
  two whole-program module checks over the compiler's own assembly (`callee_module_check.sh`,
  `type_module_check.sh`), which read FIXPOINT's `target/gas1.s`, run beside it as the
  `module-checks` stage, red when that file is missing, rather than inside E2E, where they skipped.
  The serial `scripts/full.sh` runs the same stages, in the same order.
