## e2e (DUAL-OPERAND enum derive — the `eq` shape base/derive uses). Two enum values are compared
## by a NESTED `match` (`match a { T.(v)(pa) => match b { T.(v)(pb) => pa == pb ; _ => false } }`).
## This exercises two codegen mechanisms fixed together: (1) an 8-word `Arm` (compound expr — the
## inner `match` — as an EXPRESSION-match arm body lowers correctly), and (2) nested-match SCRATCH
## DEPTH (each by-ref enum param materializes into its OWN scratch level, so the inner `match b`
## never clobbers `a`'s payload — matching params DIRECTLY, no `aa := a` copy). Equal-variant-equal-
## payload = true; different payload or different variant = false. 40 + 2 = 42.
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
  b2 := E.B(2)
  if eq(E, a5, a5) { r = r + 40 }    ## A5 == A5 → true
  if eq(E, a5, a7) { r = r + 100 }   ## A5 == A7 → false (payload differs)
  if eq(E, a5, b5) { r = r + 100 }   ## A5 == B5 → false (variant differs)
  if eq(E, b2, b2) { r = r + 2 }     ## B2 == B2 → true
  r
}
