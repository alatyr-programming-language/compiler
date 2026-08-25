## FAIL-LOUD residual for issue #43: an inferred local may compose scalar leaves, but an aggregate
## read/bind `q := xs[i].arr[j]` remains unsupported on AArch64.
## Failure-first on parent origin/main 07492f4: x86_64=42 (run exit code), AArch64=133 (brk),
## RV64=133 (ebreak), WAT=134 (unreachable).
P := struct { a : u64, b : u64 }
S := struct { pad : u64, arr : [P; 2], tail : u64 }

main := fn() -> u64 {
  mut xs := [
    S(pad = 9, arr = [P(a = 10, b = 1), P(a = 20, b = 2)], tail = 3),
    S(pad = 19, arr = [P(a = 30, b = 4), P(a = 40, b = 5)], tail = 6)
  ]
  mut i : u64 = 1
  mut j : u64 = 0
  q := xs[i].arr[j]
  if q.a != 30 or q.b != 4 { return 1 }
  42
}
