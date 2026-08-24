## e2e REJECT (check) — a `str` ARGUMENT into a `u64` PARAMETER through a UFCS method call over a
## SIMPLE-`Var` receiver. `bump(v : V, k : u64)` called as `v.bump("nope")` is the same ill-typed call
## the DIRECT spelling `bump(v, "nope")` has always been rejected for; single-file `check` used to accept
## it with rc 0 because it ran ONE parse pass with a NULL enum table, so `parser.al`'s `is_ctor` assumed
## the enum-CTOR shape for every `recv.method(args)` and built an `EnumLit` — a node sema's call-level
## battery never looks at. `check` now runs the same two-pass shape `build`/`fmt` already used.
V := struct { n : u64 }

bump := fn(v : V, k : u64) -> u64 { v.n + k }

main := fn() -> u64 {
  v := V(n = 1)
  v.bump("nope")
}
