## Store-escape via an `out` parameter (spec Memory §5.3.1): an `out` param is a reference to the
## caller's place, which outlives the callee; assigning ptr(<fn-local>) to it escapes a dead stack
## slot upward — the check must reject (rc 1). `r` is pointer-typed so the write is type-correct.
leak := fn(out r : ptr(u64)) {
  x := 5
  r = ptr(x)
}
main := fn() -> u64 { 0 }
