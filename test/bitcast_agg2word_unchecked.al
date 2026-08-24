## e2e (x86_64): verification mode must not change aggregate bitcast representation.
## Both forms reinterpret the same two-word source; q is word 1, so a word-0-only
## fallback cannot satisfy the checks.
A := struct { a : u64, b : u64 }
B := struct { p : u64, q : u64 }

main := fn() -> u64 {
  x := A(a = 40, b = 2)
  plain := bitcast(B, x)
  raw := unchecked bitcast(B, x)
  plain_sum := plain.p + plain.q
  raw_sum := raw.p + raw.q
  if plain_sum != 42 { return 0 }
  if raw_sum != plain_sum { return 0 }
  return 42
}
