## spec Types §6.2 / grammar §130 — a discriminant pin is EXACTLY `"=" int` (a single integer literal).
## An EXPRESSION pin (`= 0 - 1`) is NOT spec-legal; left tolerant, the parser would silently consume the
## leading `= 0` and mis-parse the trailing `- 1` into bogus extra variants (the same silent-mis-parse
## class the pin fix closes). It MUST fail LOUD instead. `build_reject` asserts a non-zero build rc.
Bad := enum { A = 0 - 1, B }

main := fn() -> u64 {
  x := Bad.A
  match x {
    Bad.A => { 0 }
    Bad.B => { 1 }
  }
}
