## Issue #43 bounded slice: write a whole aggregate element through an inferred homogeneous local
## struct array, with runtime outer/inner indices. Check both written fields, the neighboring element,
## and surrounding fields so a one-word or mis-strided store is observable.
## Failure-first on parent origin/main e82a54e: x86_64=42, AArch64=133, RV64=133, WAT=134.
P := struct { a : u64, b : u64 }
S := struct { pad : u64, arr : [P; 2], tail : u64 }

main := fn() -> u64 {
  mut xs := [
    S(pad = 1, arr = [P(a = 10, b = 11), P(a = 12, b = 13)], tail = 2),
    S(pad = 3, arr = [P(a = 20, b = 21), P(a = 22, b = 23)], tail = 4)
  ]
  mut i : u64 = 1
  mut j : u64 = 0
  xs[i].arr[j] = P(a = 40, b = 42)
  ## x86_64 keeps its existing aggregate bind path; AArch64 checks the two scalar leaves through its
  ## already-supported composed scalar read path. Both branches independently observe the write and
  ## its neighbors without opening aggregate read/bind for the new AArch64 slice.
  comptime if target.arch == Arch.x86_64 {
    after := xs[i].arr[j]
    neighbor := xs[1].arr[1]
    if after.a != 40 or after.b != 42 { return 1 }
    if neighbor.a != 22 or neighbor.b != 23 { return 2 }
    if xs[1].pad != 3 or xs[1].tail != 4 { return 3 }
    first := xs[0].arr[0]
    second := xs[0].arr[1]
    if first.a != 10 or first.b != 11 { return 4 }
    if second.a != 12 or second.b != 13 { return 5 }
  }
  comptime if target.arch == Arch.aarch64 {
    if xs[i].arr[j].a != 40 or xs[i].arr[j].b != 42 { return 1 }
    if xs[1].arr[1].a != 22 or xs[1].arr[1].b != 23 { return 2 }
    if xs[1].pad != 3 or xs[1].tail != 4 { return 3 }
    if xs[0].arr[0].a != 10 or xs[0].arr[0].b != 11 { return 4 }
    if xs[0].arr[1].a != 12 or xs[0].arr[1].b != 13 { return 5 }
  }
  if xs[0].pad != 1 or xs[0].tail != 2 { return 6 }
  42
}
