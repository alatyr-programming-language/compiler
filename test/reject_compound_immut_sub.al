## e2e reject (Grammar §130 line 287 · OP-2 · Declarations): `x -= e` is a WRITE to the place `x`,
## so on an IMMUTABLE binding (no `mut`) it must be a LOCATED reject — the same diagnostic a plain
## `x = e` earns (`reject_immutable_write`): "check: type mismatch at line 15" — the operator line.
##
## Whether sema sees a write at all depends on `sema::assign_is_reassign` recovering the compound
## token from source; its private table listed only `+= -= *= /=`, so the other four glyphs took the
## fresh-BINDING path and the write was ACCEPTED IN SILENCE. Eight one-operator files, not one file
## with eight writes, because the checker reports the FIRST diagnostic only — a single file would be
## rejected by its first line and prove nothing about the other seven.
##
## Measured on the pre-fix build (Stage1 from the seed at ed53617, whose `src/`+`lib/` are
## byte-identical to bd1776a, where the eight operators landed): check exit 1, "type mismatch at line 15" — the operator line (already correct)
main := fn() -> u64 {
  value : u64 = 100
  value -= 7
  return value
}
