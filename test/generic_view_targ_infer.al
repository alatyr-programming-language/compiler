## e2e (Comptime §3.3 — "comptime type-parameters are INFERRED from the types of runtime arguments
## where determinable"; Types §7 — a view is its two-word pair). A view's SLOT records the view KIND
## and never a type SPAN, so the inference could not type a `str` argument: the call then took the
## VALUE argument itself for the omitted type argument, tagged the instance with that argument's own
## NAME text and passed NO value at all — `println(s)` for a `str` local printed `0` and a user
## `fn(T : type, v : T) -> T` SIGSEGV'd. Silent wrong values (I11), in statement AND value position.
##
## CONTENT is checked, not arity: `same(s, t)` must be 0 for two DIFFERENT strings and 1 for equal
## ones, so an instance that dropped its value argument (both reading garbage) cannot score 1/0
## correctly. The explicit `same(str, …)` spelling is the POSITIVE CONTROL — the path that already
## worked and must stay byte-compatible with the inferred one (same monomorphized instance). 42.
same := fn(T : type, a : T, b : T) -> u64 {
  if str_eq(a, b) { return 1 }
  0
}

main := fn() -> u64 {
  s : str = "Alice"
  t : str = "Alicia"
  u : str = "Alice"
  mut k : u64 = 0
  k += same(s, u)                      ## T INFERRED = str — equal content
  k += same(s, t)                      ## must be 0 — different content
  k += same(str, s, u)                 ## POSITIVE CONTROL — the explicit type argument
  ## A generic whose RETURN type is its own type parameter, with the type argument INFERRED as `str`.
  ## `str_ret_call` reads that argument POSITIONALLY, so an inferred one was invisible to it: the call
  ## fell to the scalar return path. Both spellings must round-trip the CONTENT, in argument position
  ## and through a local binding.
  k += same(str, id(s), u)             ## an inferred-`str` generic result as a call ARGUMENT
  w := id(s)                           ## ... and through a LOCAL binding (both words must land)
  k += same(str, w, u)
  k += same(str, id(t), u)             ## must be 0 — a different string round-trips as itself
  if k == 4 { return 42 }
  k
}

id := fn(T : type, v : T) -> T { return v }
