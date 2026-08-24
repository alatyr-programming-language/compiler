## e2e (Types §9.4): a CHAINED field read off a by-value struct-returning call — `mk().b.c`, where
## `mk() -> Outer` and `.b` is a nested `Inner` struct. The base of the outer `Field` is itself a
## `Field` (not a bare Call), so the single-`<call>.field` arm did not match → the read fell to the
## `pushq $0` default: a SILENT 0 (`mk().b.c` read 0 instead of 33). Now `call_chain_place` walks the
## Field chain to the root call, resolves its returned struct span, and accumulates the intermediate
## word offsets; the call is materialized into the return registers and the leaf word is selected.
## `mk().b.c` = 33, plus `mk().b.d` (word 2 = %rcx) = 99 → 33 + 99 = 132; return mod 120 → keep < 126.
Inner := struct { c : u64, d : u64 }
Outer := struct { a : u64, b : Inner }
mk := fn() -> Outer { return Outer(a = 7, b = Inner(c = 33, d = 99)) }
main := fn() -> u64 {
  return mk().b.c
}
