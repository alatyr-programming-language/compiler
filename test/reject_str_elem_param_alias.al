## Issue #429 — the alias of a `str` PARAMETER, and one more hop past it. `s[0] = 65` inside this
## function was already a located reject before this change; `t := s` then `t[0] = 65` was not,
## and neither was `u := t`. A parameter binds the caller's view, so every hop names the same
## read-only bytes and none of them may be stored into.
##
## Measured on the parent (d18fb3f): built clean, x86_64 exit 139 (SIGSEGV). The reject is
## reported at the innermost write, so the fixture pins the LAST hop's line, not the parameter's.
f := fn(s : str) -> u64 {
  t := s
  u := t
  u[0] = 65
  7
}

main := fn() -> u64 { f("abc") }
