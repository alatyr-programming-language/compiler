## e2e (reject) — a digit that is not valid for the literal's base (Grammar §2.4: `bin-int` takes
## `bin-digit` only). `0b12` used to lex as `0` + the identifier `b12`, so the literal silently
## became 0. It must be a LOCATED reject instead.
main := fn() -> u64 {
  x : u64 = 0b12
  return x
}
