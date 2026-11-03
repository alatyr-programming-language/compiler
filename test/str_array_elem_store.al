## #1181 — `t[i] = <str>` into a `[str; N]` element stores the whole two-word {ptr, len} pair (Types §7),
## from a literal and from a str local. Expected exit 42; a failing check exits its own number.
## NON-VACUOUS: the parent stored the pointer word only, so the element kept its old length.
main := fn() -> u64 {
  mut s : [str; 2] = ["abc", "de"]
  s[1] = "x"
  if u64(s[1].len) * 10 + u64(s[0].len) != 13 { return 1 }
  y : str = "wxyz"
  s[0] = y
  if s[0].len != 4 { return 2 }
  if s[0] != "wxyz" { return 3 }
  42
}
## expect: run 42
