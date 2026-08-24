## @convert (Types §4.6 / TYP-6) whose target struct is >7 words → the sret return convention (the caller
## passes a hidden result pointer). Confirms the @convert dispatch routes a wide aggregate return through
## the existing sret path (via the ret_call_target hook), not only the ≤7-word register-return case.
## Big is 8 u64 words (>7); Big(42).a reads the first field. x86-only (@convert is x86-only today).
Big := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64 }
mkbig := @convert fn(x : u64) -> Big { return Big(a = x, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0) }
main := fn() -> u64 {
  v := Big(42)
  return v.a
}
