## #1719 — the receiver form of the same call, on a `str` PARAMETER rather than a literal binding:
## `s.len()` reaches the program's `len(x : u64)` with the str as its argument. After #1434 it compiled
## to an address-dependent value on native x86_64 (182, then 118; no diagnostic); the parent 263da9f6
## answered 42 through the intrinsic. Refused at the receiver until spec#166 decides the reading.
len := fn(x : u64) -> u64 { x }
g := fn(s : str) -> u64 {
  s.len() + 38
}
main := fn() -> u64 { g("abcd") }
## expect: reject "type mismatch" "at line 7"
