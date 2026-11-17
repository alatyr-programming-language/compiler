## #1719 — a range VIEW, not a str: the program's `len(x : u64)` does not accept a `Slice(u64)`. After
## #1434 it compiled and answered 238 on native x86_64 (no diagnostic); the parent 263da9f6 answered 42
## through the intrinsic. Refused at the argument until spec#166 decides shadowing against overloading.
len := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  xs : [u64; 4] = [1, 2, 3, 4]
  v := xs[0..4]
  len(v) + 38
}
## expect: reject "type mismatch" "at line 8"
