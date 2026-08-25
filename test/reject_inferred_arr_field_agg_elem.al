## FAIL-LOUD residual for issue #43: an inferred local may compose scalar leaves, but a multi-word
## aggregate leaf write with an aggregate VAR RHS remains outside the bounded literal-only slice.
## The accepted form is the direct typed literal `xs[i].arr[j] = P(...)`; this residual keeps the same
## runtime indices and root while proving that aggregate copies are still fail-loud.
## Baseline origin/main e82a54e: x86_64=0, AArch64=133, RV64=133, WAT=134; post-fix remains unchanged.
P := struct { a : u64, b : u64 }
S := struct { pad : u64, arr : [P; 2], tail : u64 }

main := fn() -> u64 {
  mut xs := [
    S(pad = 9, arr = [P(a = 10, b = 1), P(a = 20, b = 2)], tail = 3),
    S(pad = 19, arr = [P(a = 30, b = 4), P(a = 40, b = 5)], tail = 6)
  ]
  mut i : u64 = 1
  mut j : u64 = 0
  p := P(a = 70, b = 80)
  xs[i].arr[j] = p
  0
}
