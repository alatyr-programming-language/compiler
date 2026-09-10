## Issue #580, closed-set witness — BIT 3, one `pub` re-export projection.
##
## `qh_facade::math` is not a module: `math` is a re-exported alias INSIDE `qh_facade`, so the head
## resolves through the one-hop projection driver's `d_one_reexport_module` already implements.
## Kind mask exactly 8, so this fixture is the non-vacuity witness for that arm.
##
## The `module` directives are load-bearing here and cannot be dropped: the projection needs a real
## owner module for `math` to be re-exported FROM. Note that `alatyr fmt` DELETES `module` lines —
## measured on the parent, formatting `test/import_reexport.al`, which has carried the same shape
## for as long as it has existed. The formatted form of this file still compiles (flattened, the
## `pub math := std::math` alias answers the head through the alias arm instead), so the fmt corpus
## is satisfied; but the witness above is the file as written, which is what `check_accept` and
## `run_x86` compile. The formatter's data loss is a separate defect, filed on its own.
module qh_facade
pub math := std::math

module qual_head_reexport
main := fn() -> u64 {
  if qh_facade::math::floor(65.9) == 65.0 { return 65 }
  return 1
}
