## Types §7 / I11 — a `str` field of a by-value struct-returning call is a valid two-word view.
## It is intentionally used directly as a `str_eq` operand: the current lowerer has scalar call-field
## machinery but `emit_str_pair` still falls through to an empty pair for this live view expression.
## The parent compiler therefore returns 0 instead of either producing the value or rejecting it loudly.
## The fix must preserve supported local/param/global field paths and make this unsupported view path
## fail loud rather than silently compare against an empty string.
P := struct { name : str }

mk := fn() -> P {
  return P(name = "abc")
}

main := fn() -> u64 {
  if str_eq(mk().name, "abc") { return 42 }
  return 0
}
