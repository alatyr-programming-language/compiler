## Issue #429 — the same store reached through a second name. `t := s` copies the two-word view,
## not the run of bytes it points at, so the alias inherits the source's pointee permission: the
## bytes are still the literal's read-only static data (Memory §2.3), and `str` is still `[u8]`
## whose element permission comes from that pointer (Types §7 / Memory §3.3).
##
## Measured on the parent (d18fb3f): built clean, x86_64 exit 139 (SIGSEGV). The alias re-opened
## the fault for EVERY spelling of the source binding, including a `str` parameter whose own
## direct `s[i] = v` the established `immutable binding` fence already refused — so a one-word
## edit walked around it. The marker is carried across the alias, which also makes it transitive.
main := fn() -> u64 {
  s := "abc"
  t := s
  t[0] = 65
  7
}
