## Control Flow §5.4 — a v1 OR-pattern alternative may NOT bind a payload (the alternatives would
## bind inconsistently). `Some(x) | None` is ill-formed → the build FAILS LOUD (never a silent
## miscompile / crash).
main := fn() -> u64 {
  o := Option.Some(5)
  r := match o { Some(x) | None => 1 }
  return r
}
