## Issue #580, closed-set witness — BIT 0, a MODULE named by its path.
##
## `std::math` mangles onto the ambient module `std__math`, so the head resolves through the
## declaration vector's `mod_start/mod_len` — the scope the parse already recorded. Its kind mask
## is exactly 1, so this fixture is the non-vacuity witness for that arm: delete it from
## `sema::sema_qual_head_kinds` and this program stops compiling.
##
## Deliberately NOT written with a `module` directive. `alatyr fmt` DELETES those lines (measured on
## the parent, formatting `test/import_reexport.al`), so a `module`-shaped witness fails the fmt
## corpus the moment an unresolved head becomes an error rather than a silent fall-through.
main := fn() -> u64 {
  if std::math::floor(61.9) == 61.0 { return 61 }
  return 1
}
