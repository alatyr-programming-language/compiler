## e2e/fmt — the comptime VARIANT-ARM TEMPLATE in expression-match position,
## `match a { comptime for v in typeinfo(T).variants { T.(v)(pa) => … } }`, plus the comptime-VARIANT
## pattern `T.(v)(pb)` inside it. This is the shape `lib/base/derive.al` writes `eq`/`lt` in, so until
## now `alatyr fmt` REFUSED derive.al and every user file with a derive-shaped comparison
## ("comptime match arm not modelled" — `comptime_enum_eq`).
##
## The parser parses the template's ITERABLE and throws it away, and the pattern parser overwrites the
## `T` of `T.(v)` with the comptime var's own span, so neither survives in the `Arm`. Both are
## recovered by source-scan off the spans that DO survive; a failed scan still refuses loudly.
## The four `eq` calls in `main`, in order: same variant + same payload (true, +40); same variant +
## different payload (false); different variant (false); the SECOND variant (true, +2 — so the
## unroll is exercised over both variants). 42 iff every one of them answers correctly.
E := enum { A(u64), B(u64) }

eq := fn(T : type, a : T, b : T) -> bool {
  comptime match typeinfo(T) {
    Enum(_) => {
      return match a {
        comptime for v in typeinfo(T).variants {
          T.(v)(pa) => match b {
            T.(v)(pb) => pa == pb
            _ => false
          }
        }
      }
    }
    _ => { return a == b }
  }
}

main := fn() -> u64 {
  mut r : u64 = 0
  a5 := E.A(5)
  a7 := E.A(7)
  b5 := E.B(5)
  if eq(E, a5, a5) { r = r + 40 }
  if eq(E, a5, a7) { r = r + 100 }
  if eq(E, a5, b5) { r = r + 100 }
  if eq(E, b5, b5) { r = r + 2 }
  return r
}
