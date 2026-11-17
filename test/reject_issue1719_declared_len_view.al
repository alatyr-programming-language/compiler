## #1719 — a range VIEW, not a str: the program's `len(x : u64)` does not accept a `Slice(u64)`. After
## #1434 it compiled to an address-dependent value on native x86_64 (238, then 94; no diagnostic); the
## parent 263da9f6 answered 42 through the intrinsic. Refused until spec#166 decides the reading.
len := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  xs : [u64; 4] = [1, 2, 3, 4]
  v := xs[0..4]
  len(v) + 38
}
## expect: reject "type mismatch" "at line 8"
