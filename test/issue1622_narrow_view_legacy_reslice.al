## #1622 (#1651 review, B1) — a narrow-element view must not cross between a function the shared IR
## builds and one the legacy emitter emits.
##
## `main` cuts `Slice(bool)` views from its own `[bool; N]` arrays and hands them to `rd_*`, which the
## IR does not build (the float local `fz` keeps each on the legacy emitter). Each callee iterates a
## RE-SLICE of its view parameter. Types §6.4 lays a `[bool; N]` out at one byte per element and a
## `Slice(bool)` reads element `i` at `ptr + i × 1`; Stdlib appendix §3.5 makes `s[lo..hi]` the
## elements `lo..hi` of `s`. So every check below holds, on every backend.
##
## Each check owns a code from 1 up; 42 means all held.
##
## At a521f8dc (#1651's first round) x86_64's default built `main` from the IR, laying each array out at
## one byte per element, while the legacy callee's re-slice stepped one word per element: checks 1-5
## read 4, 4, 4, 14 and 4 and the program answered 1. The parent 9e60e8aa and `x86-legacy` keep both
## sides on the legacy layout and answer 42. Since the fix, a caller the IR builds never passes a
## narrow-element view to a legacy-emitted function: `main` falls back to legacy (`x86_isel_plan`).
## aarch64, riscv64 and wasm keep this program on legacy, where the slice argument is a fail-loud stub:
## known deviations under #1288.
rd_a := fn(s : Slice(bool)) -> u64 {
  fz := 1.5
  mut r : u64 = 0
  for x in s[1..3] { r = r * 3 + (if x { 1 } else { 2 }) }
  r
}
rd_b := fn(s : Slice(bool)) -> u64 {
  fz := 1.5
  mut r : u64 = 0
  for x in s[1..4] { r = r * 3 + (if x { 1 } else { 2 }) }
  r
}
rd_c := fn(s : Slice(bool)) -> u64 {
  fz := 1.5
  u := s[1..s.len]
  mut r : u64 = 0
  for x in u { r = r * 3 + (if x { 1 } else { 2 }) }
  r
}

main := fn() -> u64 {
  a1 : [bool; 4] = [false, true, false, true]
  if rd_a(a1[0..4]) != 5 { return 1 }
  a2 : [bool; 4] = [true, true, false, false]
  if rd_a(a2[0..4]) != 5 { return 2 }
  a3 : [bool; 4] = [false, false, true, true]
  if rd_a(a3[0..4]) != 7 { return 3 }
  a4 : [bool; 4] = [true, false, true, true]
  if rd_b(a4[0..4]) != 22 { return 4 }
  a5 : [bool; 3] = [true, false, true]
  if rd_c(a5[0..3]) != 7 { return 5 }
  42
}
## expect: run 42
