- **`check` on a single-file package with a manifest binding no longer depends on a stray register
  (#1822).** The `check` path built the manifest's hidden `Package` type with one argument too few,
  so its field count was whatever the register held: harmless by luck under seed 0.5.0, a
  `rt: StrBuf overflow` once the caller next to it is emitted from the shared IR. It now passes the
  count the build path passes. The checker hole that accepted the short call is #1822.
