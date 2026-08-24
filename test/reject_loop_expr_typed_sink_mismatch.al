## P1-BREAK: a value-loop's known break type must match its typed local sink.
main := fn() -> u64 {
  x : bool = loop { break 1 }
  return 42
}
