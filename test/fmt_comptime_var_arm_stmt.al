## e2e/fmt — the comptime-variant pattern `T.(v)(pb)` as an arm of a STATEMENT match (braced arm
## bodies) inside the comptime variant unroll. `lib/base/derive.al`'s `eq` takes this shape since
## #1369; `alatyr fmt` refused it with a panic, so the source formatting walk failed on derive.al.
## The four `eq` calls in `main`, in order: same variant + same payload (true, +40); same variant +
## different payload (false); different variant (false); the SECOND variant (true, +2). 42 iff every
## one of them answers correctly.
E := enum { A(u64), B(u64) }

eq := fn(T : type, a : T, b : T) -> bool {
  comptime match typeinfo(T) {
    Enum(_) => {
      match a {
        comptime for v in typeinfo(T).variants {
          T.(v)(pa) => {
            match b {
              T.(v)(pb) => { return pa == pb }
              _ => { return false }
            }
          }
        }
      }
      return false
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
## expect: run 42
