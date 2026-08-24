## FN-6 — a MULTI-parameter inline function value. A 2+-param lambda previously saw only its first
## parameter: the parser links each extra `Param` by storing `.next` through a pointer, and a
## `deref(ptr) = Param(...)` inline-ctor store mis-lowers in the seed (the store-through-pointer
## scar), silently dropping the link — so the §1 spill count (`d.arity`) came out 1 and the second
## argument aliased the first (`add(40, 2)` returned 80 = 40 + 40). Building the updated `Param` in a
## local before the store fixes it. `add(40, 2) + sub` exercises 2- and 3-param lambdas at once.
add := fn(a : u64, b : u64) -> u64 { return a + b }
main := fn() -> u64 {
  f2 := fn(a : u64, b : u64) -> u64 { return a + b }
  f3 := fn(a : u64, b : u64, c : u64) -> u64 { return a + b + c }
  return f2(20, 2) + f3(10, 6, 4)
}
