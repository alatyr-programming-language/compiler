## e2e BUILD-REJECT (correct-or-trap). A module-level GLOBAL whose initializer is a runtime CALL
## returning an AGGREGATE. A global's storage is emitted as `.data` cells folded from a COMPILE-TIME
## constant initializer, and nothing runs before `_start` — so this global got ZEROED (or no) storage
## and `mk()` was never called: `G.a + G.b` silently read 0 instead of 11. A SILENT MISCOMPILE, and the
## nastier half of an asymmetry: the SCALAR dual (`G := mk()` with `mk -> u64`) is already fail-loud
## (its value is inlined at each use → an `undefined reference` at `ld`), while the aggregate case
## exited 0 with a wrong value.
## The build now REJECTS it. Whether a global initializer may run at start-up at all — and in what
## order — is a spec question; until it is decided, rejecting beats miscompiling. A global
## initialized by a struct/enum/array/str LITERAL is unaffected and still lowers (see `agg_arr_global_rw`).
S := struct { a : u64, b : u64 }
mk := fn() -> S {
  return S(a = 5, b = 6)
}
G := mk()
main := fn() -> u64 {
  return u64(G.a + G.b)
}
