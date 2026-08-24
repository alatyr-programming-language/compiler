## FN-6 CAPTURE of an AGGREGATE — a lambda capturing a struct local `p` (bound by a `P(...)` literal, so
## the lift resolves its type P and gives the capture a TYPED by-reference param). `p.x + p.y` = 42. The
## injected call arg passes the struct local by reference. An enum capture (incl. via a `match` body)
## works the same way.
P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  p := P(x = 40, y = 2)
  c := 0
  f := fn(n : u64) -> u64 { return n + p.x + p.y + c }
  return f(0)
}
