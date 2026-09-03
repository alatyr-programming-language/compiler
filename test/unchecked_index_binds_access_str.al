## #410, `str` bases — the companion to `test/unchecked_index_binds_access.al`, which covers the
## fixed-array and typed-slice bases. Same defect, same cause: `unchecked s[i]` parsed as
## `(unchecked s)[i]`, so the byte read went to frame SLOT 0 instead of the string's storage
## (Types §6.4: inside an `unchecked` scope only the BOUNDS CHECK is omitted, never the address).
##
## Measured on the parent, both rows read slot 0 and returned their failure code; the checked reads
## were right:
##
##   `str` local     `u64(unchecked s[1])`     → 0  (want 99)   ## rc 111
##   `str` literal   `u64(unchecked "Kc"[1])`  → 0  (want 99)   ## rc 112
##
## `"Kc"` gives non-zero, pairwise-distinct neighbours ('K' = 75, 'c' = 99), so a slot-0 read cannot
## look like a plausible byte, and each check owns its own failure code from 100 (#386). The `str`
## index surface is x86_64-only today (#405/#394): on the parent AND with this fix AArch64 and
## RISC-V64 trap (133) and WAT traps (134) on this program — never a second wrong value — so the
## cross-target radius of the parser fix is carried by the scalar companion fixture, which all four
## backends run to 42.
main := fn() -> u64 {
  ## a `str` LOCAL base — a byte read, 'c' = 99.
  s := "Kc"
  if u64(unchecked s[1]) != 99 { return 111 }
  ## a `str` LITERAL base — the spelling the defect was first reported through.
  if u64(unchecked "Kc"[1]) != 99 { return 112 }
  return 42
}
