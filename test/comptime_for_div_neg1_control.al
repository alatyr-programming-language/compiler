## e2e (#1233, acceptance 3) — the control beside the `MIN / -1` diagnostic: a signed `/ -1` whose
## dividend is NOT the minimum still folds in a `comptime for` range bound, checked and inside
## `unchecked` alike. Comptime §2.6 (pinned 1.8.0) keeps only `MIN / -1` a diagnostic; `-9 / -1` is 9.
## A guard that caught every `/ -1` would refuse this file, and one that read 0 would exit 1 or 2.
main := fn() -> u64 {
  mut a : u64 = 0
  comptime for i in 0 .. unchecked ((0 - 9) / (0 - 1)) { a = a + 1 }
  if a != 9 { return 1 }
  mut b : u64 = 0
  comptime for i in 0 .. ((0 - 9) / (0 - 1)) { b = b + 1 }
  if b != 9 { return 2 }
  return 42
}
## expect: run 42
