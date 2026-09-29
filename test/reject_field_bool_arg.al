## #726 / Types §4.2, §4.3 — a field read has the field's declared type, and `bool` to an integer is
## the numeric class, always explicit, so a `bool` field is not a `u64` argument. The parent accepted
## this and ran it to 42 (`true` passed as 1): `check_expr`'s `Field` arm, which answers the field's
## type, had never run. `widen(u64(s.ok))` is the conforming spelling.
S := struct { ok : bool, n : u64 }
widen := fn(n : u64) -> u64 { n + 41 }
flagged := fn(s : S) -> u64 { widen(s.ok) }

main := fn() -> u64 {
  return flagged(S(ok = true, n = 0))
}
