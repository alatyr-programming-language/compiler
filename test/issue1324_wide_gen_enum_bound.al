## e2e / issue #1324 — a generic `-> T` call at an enum wider than seven words, bound to a local, then passed.
##
## `Option(S9)` is one discriminant word plus nine payload words. A generic instance returning its
## type parameter has no hidden-result-pointer path for an enum yet, and the register convention stops
## at seven words, so the payload's tail is lost. Until #1324 delivers the value, the build refuses the
## call with a located diagnostic.
##
## Parent `992bd767` (x86_64, omen): built rc 0 and returned 10 (wrong value).
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }
mk := fn(T : type, x : T) -> T { x }
ow := fn(o : Option(S9)) -> u64 {
  match o {
    Option::Some(s) => { s.a + s.i }
    Option::None => { 99 }
  }
}
main := fn() -> u64 {
  x := mk(Option(S9), Option(S9).Some(S9(a = 40, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0, i = 2)))
  if ow(x) != 42 { return 10 }
  42
}
