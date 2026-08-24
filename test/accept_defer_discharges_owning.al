## DEFER + LINEARITY (spec Memory §5.8/§5.9, Control Flow §9.3 / D86): `defer` is the idiom that
## discharges an @owning value's linear obligation on every normal exit. Here `h` (an @owning handle) is
## consumed by a DEFERRED `close_it(h)`; the discharge is registered before the fn ends, so the leak
## check must ACCEPT (rc 0) — the deferred consumer is a real use of `h`. (Contrast `reject_leak_owning`,
## where the same handle is dropped on the floor with no consumer and IS rejected.)
Owned := @owning struct { v : u64 }
mk := fn() -> Owned { Owned(v = 5) }
close_it := fn(o : Owned) -> u64 { 0 }
main := fn() -> u64 {
  h := mk()
  defer close_it(h)
  0
}
