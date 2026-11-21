## Issue #1808 — an alias of a type-function instance, `P := Box(u64)`, is the type `Box(u64)`
## (Declarations §1.3, Types §4.1), and a generic instantiated at `P` reads its field `w` at offset 8:
## 42. An earlier revision of the #1808 fix bound the instance's body to the alias's right-hand side
## instead of the span the caller wrote, and the written-out `Box(u64)` read `w` as 0 (#1850).
Box(T) := struct { v : T, w : T }
P := Box(u64)
Two := struct { a : u64, b : u64 }
rw := fn(T : type, h : usize) -> u64 { p : ptr(T) = unchecked bitcast(ptr(T), h); u64(deref(p).w) }
main := fn() -> u64 {
  mut t : Two = Two(a = 10497, b = 42)
  rw(P, unchecked bitcast(usize, ptr(t)))
}
## spec: Declarations §1.3; Types §4.1; Comptime §3.2
## expect: run 42
