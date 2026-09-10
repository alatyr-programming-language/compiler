## Issue #580 — an `@extern` import is NOT an unresolved name.
##
## The owner's rule says a non-existent, NON-EXTERNAL name must be refused, and Modules §7 makes
## the boundary exact: a bodyless `name := @extern fn(…)` import is an ordinary declaration in the
## same vector as everything else, so a head that reaches one resolves like any other module head.
## This is the fixture that keeps the rule from refusing FFI. `check` only — the point is the
## resolution, not a link against a C object, so it is registered as `check_accept` and never built.
##
## The `module` directives are load-bearing: the risk this guards is a module of `@extern` imports
## becoming unnameable as a `::` head, which needs a module to exist. `alatyr fmt` DELETES `module`
## lines (measured on the parent, formatting `test/import_reexport.al`); the fmt corpus does not see
## a regression here because this file never links either way, and `check_accept` does not format.
## The formatter's data loss is a separate defect, filed on its own.
module qual_head_extern_ffi
pub c_answer := @extern fn(x : u64) -> u64

module qual_head_extern
main := fn() -> u64 {
  qual_head_extern_ffi::c_answer(67)
}
