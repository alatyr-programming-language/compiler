## BUILD/CHECK-REJECT: an inferred mutable STRUCT global initialized by a runtime call still has a
## concrete struct target. A later non-literal whole-value assignment must be fenced before backend
## emission; otherwise backends without the x86 lower's field-read guard can silently store word zero.
R := struct { a : u64, b : u64 }
mk0 := fn() -> R { R(a = 0, b = 0) }
mk1 := fn() -> R { R(a = 12, b = 30) }
mut G := mk0()
main := fn() -> u64 {
  G = mk1()
  G.a + G.b
}
