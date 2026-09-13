## e2e — issue #693, position 1 of 7: a field access on an ENUM-typed value in TAIL position.
##
## `v` holds `E.B(11, 22)`. An enum value is a discriminant plus the payload of ONE variant; it has
## no member table, so `v.a` names nothing at all — `a` is not a member of `E`, and neither is any
## other spelling. Measured on this fixture's parent commit, `check` exited 0, `-o` exited 0, and the
## built program exited 0: the read answered a fabricated word the program never wrote.
##
## The refusal is a `check`-phase one, so all four backends produce it byte-identically.
E := enum { A, B(u64, u64) }
main := fn() -> u64 {
  v := E.B(11, 22)
  v.a
}
