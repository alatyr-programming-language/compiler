## Types §4.6 settles what looked like a live escape hatch: a user conversion-constructor "fires ONLY
## through an explicit `T(v)`; it is never an implicit conversion". So no in-scope `@convert` can make
## a bare `x : S = "abc"` conform — `S("abc")` is the spelling that does.
S := struct { a : u64, b : u64 }
main := fn() -> u64 {
  x : S = "nope"
  return x.a
}
