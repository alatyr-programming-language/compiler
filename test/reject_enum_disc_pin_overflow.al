## §6.2 / Types §9.1 — a discriminant pin is an integer literal and must reject when
## it does not fit in 64 bits, with the parser's located literal diagnostic.
Bad := enum { A = 18446744073709551616 }

main := fn() -> u64 {
  x := Bad.A
  0
}
