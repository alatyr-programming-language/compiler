## the matching case must still pass: a `ptr(mut A)` flows into a `ptr(mut A)` param.
A := struct { x : u64 }
takesA := fn(p : ptr(mut A)) -> u64 { return deref(p).x }
useA := fn(q : ptr(mut A)) -> u64 { return takesA(q) }
main := fn() -> u64 {
  mut a := A(x = 42)
  return useA(ptr(a))
}
## expect: run 42
