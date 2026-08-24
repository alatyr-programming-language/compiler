## sema/§ limits (I5/I9, FND-10): a translation unit declaring `@limits(no_comptime)` must NOT use a
## comptime construct — a `comptime if`/`for`/`match` in a fn body violates the unit's contract → REJECT.
@limits(no_comptime)
f := fn() -> u64 {
  comptime if target.arch == Arch.x86_64 { return 7 } else { return 8 }
}
main := fn() -> u64 { return f() }
