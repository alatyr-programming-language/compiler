## #1361 — a struct-element `Slice(P)` parameter passed on as `g(xs)` reaches the callee as the
## caller's own two-word pair (Types §7), so a range slice of it in the callee, `xs[1..xs.len]`, has
## the remaining elements. Expected exit 42; each check returns its own code.
## Parent `bd55f8e2` of #1555 (x86_64, omen): built, and ran to 1 (the range's length) from both
## build-then-run and `alatyr run`; written alone the length was 31 (build-then-run) and 255 (`run`).
P := struct {
  a : u64,
  b : u64,
}

g := fn(xs : Slice(P)) -> u64 {
  ys := xs[1..xs.len]
  if ys.len != 2 {
    return 1
  }
  ys[0].b * 10 + ys[1].b
}

f := fn(xs : Slice(P)) -> u64 {
  g(xs)
}

main := fn() -> u64 {
  t : [P; 3] = [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  r := f(t[0..3])
  if r == 1 {
    return 1
  }
  if r != 46 {
    return 2
  }
  42
}
## expect: run 42
