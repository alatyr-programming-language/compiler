## e2e (Grammar §130 line 287 · OP-2 · Memory §1): compound assignment on the DEEPER place
## forms — a tuple component, a pointer dereference, a nested tuple component, a nested field
## path, an array that is a struct field, a field of an array-of-struct element, an array field
## of an array element, a nested field path under an array element, and a field through a
## pointer. Each silently dropped its store before the fix, for all eight operators including
## `+=` (see compound_assign_place.al's header for the measurement).
##
## x86_64-only by measurement, and NOT because of compound assignment: the PLAIN `=` store on
## each of these places traps on exactly the same backends, so the compound form is precisely as
## portable as the store it desugars to. Measured, compound vs the plain `=` control, as
## x86 / a64 / rv64 / wasm:
##
##   t.0 ^= 7           alone  42/42/42/42     with array locals  42/42/42/trap  (plain `=` too)
##   v.f[1] *= 2        alone  42/42/42/42     with array locals  42/42/42/trap  (plain `=` too)
##   deref(p) |= 7             42/42/42/trap                      plain `=`: 42/42/42/trap
##   t.0.1 %= 7                42/trap/trap/trap                  plain `=`: 42/trap/trap/trap
##   o.a.b -= 7                42/trap/trap/42                    plain `=`: 42/trap/trap/42
##   xs[0].f /= 7              42/42/42/42                        (portable; grouped here)
##   xs[0].arr[1] |= 7         42/trap/trap/42                    plain `=`: 42/trap/trap/42
##   xs[0].a.b ^= 7            42/trap/trap/42                    plain `=`: 42/trap/trap/42
##   deref(p).f &= 7           42/trap/trap/trap                  plain `=`: 42/trap/trap/trap
##
## A trap is acceptable; a wrong value is not — and no backend returns a wrong value here.
##
## Expected exit: 42 (every place agrees). A failure exits 100 + the place's 1-based index.
V := struct { f : [u64; 3] }
E := struct { arr : [u64; 2] }
B := struct { b : u64 }
A := struct { a : B }
P := struct { f : u64 }
main := fn() -> u64 {
  mut bad : u64 = 0
  ## 1. `t.N op=` — a tuple component
  mut t1 := (100, 7)
  t1.0 ^= 7
  if bad == 0 and t1.0 != 99 { bad = 1 }
  ## 2. `deref(p) op=` — a store through a pointer
  mut x2 : u64 = 100
  p2 := ptr(mut x2)
  deref(p2) |= 7
  if bad == 0 and x2 != 103 { bad = 2 }
  ## 3. `t.N.M op=` — a nested tuple component
  mut t3 := ((1, 100), 3)
  t3.0.1 %= 7
  if bad == 0 and t3.0.1 != 2 { bad = 3 }
  ## 4. `o.i.v op=` — a nested field path
  mut o4 := A(a = B(b = 100))
  o4.a.b -= 7
  if bad == 0 and o4.a.b != 93 { bad = 4 }
  ## 5. `v.field[i] op=` — an array that is a struct field
  mut v5 := V(f = [1, 100, 3])
  v5.f[1] *= 2
  if bad == 0 and v5.f[1] != 200 { bad = 5 }
  ## 6. `xs[i].f op=` — a field of an array-of-struct element
  mut xs6 : [P; 2] = [P(f = 100), P(f = 1)]
  xs6[0].f /= 7
  if bad == 0 and xs6[0].f != 14 { bad = 6 }
  ## 7. `xs[i].arr[j] op=` — an array field of an array element
  mut xs7 : [E; 1] = [E(arr = [1, 100])]
  xs7[0].arr[1] |= 7
  if bad == 0 and xs7[0].arr[1] != 103 { bad = 7 }
  ## 8. `xs[i].a.b op=` — a nested field path under an array element
  mut xs8 : [A; 1] = [A(a = B(b = 100))]
  xs8[0].a.b ^= 7
  if bad == 0 and xs8[0].a.b != 99 { bad = 8 }
  ## 9. `deref(p).field op=` — a field write through a pointer
  mut s9 := P(f = 100)
  p9 := ptr(mut s9)
  deref(p9).f &= 7
  if bad == 0 and s9.f != 4 { bad = 9 }
  if bad != 0 { return 100 + bad }
  return 42
}
