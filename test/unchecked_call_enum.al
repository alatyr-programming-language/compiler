## #1139 — an enum with a struct payload returned by a call under the grant `unchecked find(41)`.
## Expected exit 42.
S := struct { a : u64, b : u64, c : u64 }
find := fn(n : u64) -> Option(S) { Option.Some(S(a = 1, b = n, c = 0)) }
main := fn() -> u64 {
  o := unchecked find(41)
  match o {
    Some(s) => { s.a + s.b }
    None => { 7 }
  }
}
## expect: run 42
