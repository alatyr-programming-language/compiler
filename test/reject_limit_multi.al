## sema/§ limits: a MULTI-limit `@limits(no_alloc, no_comptime)` records the WHOLE list, so no_comptime
## is enforced even when it is not the first limit → a comptime construct here REJECTS. (Regression for
## the marker's full-list span + the arity-99 sentinel + the per-limit substring scan.)
@limits(no_alloc, no_comptime)
f := fn() -> u64 {
  comptime if target.arch == Arch.x86_64 { return 7 } else { return 8 }
}
main := fn() -> u64 { return f() }
