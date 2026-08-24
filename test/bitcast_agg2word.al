## e2e (aggregate→aggregate bitcast copies BOTH words). Reinterpreting one 2-word struct as another
## 2-word struct via `bitcast` must carry word 0 AND word 1. Previously copied word 0 only, zeroing
## word 1. Here bitcast A{a=40,b=2} to B{p,q}: p+q must be 42.
A := struct { a : u64, b : u64 }
B := struct { p : u64, q : u64 }
main := fn() -> u64 {
  x := A(a = 40, b = 2)
  y := bitcast(B, x)
  return y.p + y.q
}
