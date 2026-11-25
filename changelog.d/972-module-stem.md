- A scanned source file or directory whose stem is not an identifier (`src/a-b.al`, `src/2d.al`,
  `src/fn.al`, a directory `src/my-lib/`) is now refused with a Config diagnostic located by its path
  (spec#192, recorded as MOD-17 after the pinned 1.12.0). A contextual keyword stem (`out`, `scoped`)
  is refused too while spec#199 is open. Newly rejecting a program the spec declares invalid is a
  PATCH.
