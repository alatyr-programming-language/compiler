- The root file of a manifest-less invocation is the anonymous root module for a lone file too (Tooling
  §4), so its stem no longer reaches a symbol: `alatyr hyphen-test.al` used to emit `hyphen-test__main`,
  which `as` refused on x86_64 and aarch64, and now emits `main` on all four backends (#972).
- A scanned source file or directory whose stem is not an identifier (`src/a-b.al`, `src/2d.al`,
  `src/fn.al`, a directory `src/my-lib/`) is now refused with a Config diagnostic located by its path
  (spec#192, recorded as MOD-17 after the pinned 1.12.0). A contextual keyword stem (`out`, `scoped`)
  is refused too while spec#199 is open. Newly rejecting a program the spec declares invalid is a
  PATCH.
