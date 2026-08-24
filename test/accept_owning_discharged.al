## The @owning handle IS discharged (forget) before the fn ends — no leak, check ACCEPTS. Guards against
## a false positive in leak-detection (a used/discharged owning handle must not be flagged).
Owned := @owning struct { v : u64 }
mk := fn() -> Owned { Owned(v = 5) }
main := fn() -> u64 {
  h := mk()
  forget(h)
  0
}
