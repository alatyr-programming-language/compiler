## e2e (Types §9.4 / FN-7): a UFCS method on a generic-enum-returning CALL receiver —
## `find(1).unwrap()`, where `find(k) -> Option(u64)`. The parser desugars this to
## `unwrap([find(1)])`; the receiver `find(1)` is a Call with no name, so the implicit-UFCS type-arg
## inference (`infer_implicit_targ`/`infer_implicit_pre`) could not recover `T` from it → `did_impl`
## stayed false, `nvals` collapsed to 0, and the receiver arg was dropped entirely — a `call unwrap`
## with NO args set up → SEGFAULT. Now the receiver's return type resolves via `recv_call_full_span`
## and `T` is tagged by the concrete (scalar) payload type, so the call result is materialized and
## passed by reference as `self`. The bound form `r := find(1); r.unwrap()` already worked. = 42.
find := fn(k : u64) -> Option(u64) {
  if k == 1 { return Option(u64).Some(42) }
  return Option(u64).None
}
main := fn() -> u64 {
  return find(1).unwrap()
}
