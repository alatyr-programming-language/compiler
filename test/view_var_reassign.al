## e2e — REGRESSION LOCK for the RE-ASSIGN half of the view-copy miscompile (Types §9.4): `r = <str
## var>` into an ALREADY-bound `str` local kept the destination's OLD length word. Only word 0 (the
## data pointer) was stored, so the pair became {new ptr, stale len} — a str pointing at fresh bytes
## with the previous value's length. This is the shape the COMPILER'S OWN SOURCE hit, and fixing it
## changed exactly four emitted call sites:
##
##   `src/aarch64.al` / `src/riscv64.al` / `src/wat.al` — `*_operand_narrow`: `mut r := ""` … `r = nn`.
##     `r` kept `""`'s length 0, so the following `if r == ""` was ALWAYS true and the PARAM-derived
##     narrow type was silently discarded in favour of the local-derived one.
##   `src/cli.al` — `manifest_profile_flags`: `mut dv : str = mf_token(…)` … `dv = ov`. A per-profile
##     flag OVERRIDE took the default's length, truncating/extending the override's text.
##
## Values: 4 + 2 + 5 = 11.

## the `mut r := ""` … `r = <str var>` shape (an empty destination keeping length 0)
pick := fn(k : u64) -> str {
  mut r := ""
  n := "abcd"
  if k == 1 { r = n }
  if r == "" { return "zz" }
  return r
}

## the `mut dv : str = <str-returning value>` … `dv = <str var>` shape (a LONGER destination length)
override := fn() -> u64 {
  mut dv : str = "abcdefg"
  ov := "hi"
  dv = ov
  return u64(dv.len)
}

main := fn() -> u64 {
  z := pick(1)
  if u64(z.len) != 4 { return 1 }
  if u64(bytes(z)[0]) != 97 { return 2 }
  if override() != 2 { return 3 }
  y := pick(0)
  if u64(y.len) != 2 { return 4 }
  return u64(z.len) + override() + u64(y.len) + 3
}
