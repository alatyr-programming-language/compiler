## #1243 — an array literal of struct-returning calls. Its element kind is the call's return type (Types
## §6.4), as a struct literal's is. The issue's own program, verbatim: 7 * 10 + 5 = 75.
## NON-VACUOUS: on the parent da8f96af (native x86_64, tree Stage1) x86 and x86-ir answer 50: the call
## element took the scalar element kind, so `x.a` and `y.a` read one slot below what their bindings wrote.
S1 := struct { a : u64 }
mk := fn(k : u64) -> S1 { S1(a = k) }
main := fn() -> u64 {
  a : [2]S1 = [mk(5), mk(7)]
  x := a[1]
  y := a[0]
  return x.a * 10 + y.a
}
## expect: run 75
