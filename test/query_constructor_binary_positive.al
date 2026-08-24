## QUERY regression: valid constructor and scalar-binary operands remain queryable.
## The negative companion locks the aggregate-binary rejection separately.
S := struct { a : u64 }
@inline + := fn(x : S, y : u64) -> u64 { x.a + y }
good_ctor := compiles(S(a = 1))
good_binary := compiles(1 + 1)
good_overload := compiles(S(a = 40) + 2)

main := fn() -> u64 {
  if good_ctor and good_binary and good_overload { return S(a = 40) + 2 } else { return 1 }
}
