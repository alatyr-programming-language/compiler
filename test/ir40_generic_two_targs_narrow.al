## IR-40 (#1786): an IR-built call to a generic instance with two written type arguments, and results
## of the type argument's own width. `second(u8, i16, a, b)` names the instance `second(u8, i16)`: both
## type arguments are erased from the value arguments, as the legacy caller erases them, so `b` arrives
## in the callee's second value slot. `same(u8, v)` returns a `u8` and `same(i16, v)` an `i16`: the IR
## caller re-canonicalizes each result at its width, zero-extended for `u8` and sign-extended for `i16`.
## A swapped pair of arguments answers 3 or 4; a `u8` read as signed answers 5; an `i16` read unsigned 6.
second := fn(A : type, B : type, a : A, b : B) -> B { b }
same := fn(T : type, v : T) -> T { v }
two := fn(a : u8, b : i16) -> i16 { second(u8, i16, a, b) }
wide := fn(v : u8) -> u8 { same(u8, v) }
neg := fn(v : i16) -> i16 { same(i16, v) }
main := fn() -> u64 {
  r : i16 = two(9, -3)
  if r == 9 { return 3 }
  if r != -3 { return 4 }
  w : u8 = wide(250)
  if w != 250 { return 5 }
  n : i16 = neg(-30000)
  if n > 0 { return 6 }
  if n != -30000 { return 7 }
  u64(r + 45)
}
## expect: run 42
