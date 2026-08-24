## ROADMAP §1 item 3: resolve overloads by the COMPLETE signature, not a first-argument heuristic.
## Two same-name overloads share their first parameter type (u64) and differ only in the SECOND
## (A vs B). The old first-argument mangling collided both to `__u64`, so the assembler rejected the
## duplicate symbol; the full-signature suffix (`__u64_A` / `__u64_B`) keeps them distinct, and the
## call resolves to the right one by matching every inferable argument type.
A := struct { v : u64 }
B := struct { v : u64 }
f := fn(x : u64, a : A) -> u64 { return x + a.v + 100 }
f := fn(x : u64, b : B) -> u64 { return x + b.v + 200 }
main := fn() -> u64 {
  a := A(v = 1)
  b := B(v = 2)
  ## f(10,a) = 111, f(10,b) = 212 → 212 - 111 - 59 = 42 (no under/overflow: the checked `+` guard,
  ## I11 / CG-8, would trap the old `111 - 212 + 143` which added 143 to an underflowed u64).
  return f(10, b) - f(10, a) - 59
}
