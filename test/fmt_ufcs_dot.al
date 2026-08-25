## fmt fixture — the DOT call (Functions §7.2 UFCS + Types §5.3 enum construction). The parser
## desugars `recv.method(args)` to `Call(method, [recv, args…])`, and it takes the SAME path for
## `E.V(args)` when `E`'s decl is not in this file (fmt's enum table holds only local decls — every
## stdlib `Option`/`Result` construction lands there). Rendered literally that is a DIFFERENT
## program: the dot-call on `r` came back as `unwrap(r)` (check: unbound name) and `Option.Some(40)` as
## `Some(Option, 40)` (the enum TYPE passed as a value argument). Returns 42.
Pair := struct { a : u64, b : u64 }

## A UFCS-callable method over a local struct — `p.total()`.
total := fn(p : Pair) -> u64 {
  return p.a + p.b
}

## GUARD: the callee below OPENS its line, immediately after a comment ending in a full stop. The
## dot-call probe scans backwards from the callee name for a `.`; if it may cross a newline it finds
## THIS full stop and renders `size(Pair)` as `(Pair).size()`. The scan must stop at the line break.
Sixteen :=
  size(Pair)

main := fn() -> u64 {
  o : Option(u64) = Option.Some(20)
  r : Result(u64, u64) = Result.Ok(10)
  mut t : u64 = 0
  match o { Option::Some(v) => { t = v } Option::None => { t = 0 } }
  t = t + r.unwrap()
  p := Pair(a = 2, b = 4)
  t = t + p.total()
  t = t + Sixteen - 10
  return t
}
