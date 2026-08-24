## CT-12 / Comptime §2.6: a checked comptime overflow in a return expression is
## diagnosed at the arithmetic site because the declared return type supplies the
## integer context (Types §9.1).
overflow := fn() -> u64 {
  return 18446744073709551615 + 1
}

main := fn() -> u64 {
  return overflow()
}
