## BREAK: a value-loop's common break type matches its typed local sink.
main := fn() -> u64 {
  x : bool = loop { break true }
  return 42
}
