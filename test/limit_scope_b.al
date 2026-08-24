## Paired with limit_scope_a.al: this file uses a `comptime if` but declares NO `@limits`, so it is
## unrestricted. A per-file (I9) check of `A B` must ACCEPT — A's `no_comptime` is A's contract only.
bb := fn() -> u64 { comptime if target.arch == Arch.x86_64 { return 41 } else { return 8 } }
main := fn() -> u64 { return bb() + aa() }
