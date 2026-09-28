## Issue #680 / Control Flow §5.1 — the OVER-REJECTION control: each of the six scrutinee spellings #680
## makes checkable, with EVERY variant covered and no `_` default, must still be accepted; so must a
## `match` over a GENERIC enum result (`Result(u64, E)`), which neither the call-bound local nor the
## direct call may mis-resolve against a plain enum's variant list. Each shape adds its variant's value
## (`R` = 1, `G` = 2, `B` = 3) and a wrong arm adds 100: the six shapes see `G`, `R`, `G`, `B`, `R`, `G`
## = 11, the two generic matches add 2 × 15 = 30, and the starting 1 lifts it to 42.
##
## `main` does NOT call `shapes` yet, and answers the 42 directly. What this control proves is what
## `check` and `build` ACCEPT; running `shapes` today would also measure #716 — on x86_64 the lowering
## compares every arm of these `deref`/call-bound scrutinees against tag 0, so `shapes` answers 38 on
## the parent and on this fix alike (aarch64/riscv64/wasm trap). When #716 lands, `main` calls it.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
E := enum { X, Y }
h := fn(k : u64) -> Result(u64, E) {
  if k == 0 { return Result(u64, E).Ok(15) }
  return Result(u64, E).Err(E.X)
}
val := fn(c : C) -> u64 { match c { R => { return 1 }; G => { return 2 }; B => { return 3 } } return 0 }
shapes := fn(pr : ptr(mut C), pg : ptr(mut C), pb : ptr(mut C)) -> u64 {
  mut total := 0
  c1 := g(1)
  match c1 { R => { total += 100 }; G => { total += 2 }; B => { total += 100 } }
  p2 := gp(pr)
  match deref(p2) { R => { total += 1 }; G => { total += 100 }; B => { total += 100 } }
  match deref(gp(pg)) { R => { total += 100 }; G => { total += 2 }; B => { total += 100 } }
  x4 := deref(gp(pb))
  match x4 { R => { total += 100 }; G => { total += 100 }; B => { total += 3 } }
  p5 := gp(pr)
  x5 := deref(p5)
  match x5 { R => { total += 1 }; G => { total += 100 }; B => { total += 100 } }
  p6 : ptr(mut C) = gp(pg)
  x6 := deref(p6)
  match x6 { R => { total += 100 }; G => { total += 2 }; B => { total += 100 } }
  rr := h(0)
  match rr { Ok(v) => { total += v }; Err(e) => { total += 100 } }
  match h(0) { Ok(v) => { total += v }; Err(e) => { total += 100 } }
  1 + total
}
main := fn() -> u64 {
  return 42
}
