## e2e — Types §9.4, the ENUM half of `gen_struct_ret_agg_targ`: a GENERIC fn returning a
## GENERIC-STRUCT APPLICATION over its own type parameter (`mkbox(T, x) -> Box(T)`) instantiated at an
## ENUM type argument. The un-resolved `Box(T)` sizes the field `v : T` as ONE word, so the wrapped
## enum's DISCRIMINANT came back as garbage (the by-ref argument POINTER) and its payload never came
## back at all. The visible symptom is the nastiest kind: a two-arm `match o.v` matched NEITHER arm —
## both arms compared against discriminant 0 — so the accumulator was returned UNCHANGED and the
## program looked like it had simply done nothing.
##
## Covers: the `Some` and the `None` instantiation (both must select their OWN arm), and the same enum
## read back OUT through a generic-struct PARAM (`unbox(Option(u64), s)`) — whose enum type-argument is
## written as a generic INSTANCE `Option(u64)`, a `Call`, not a bare type name.
## Returns 2 + 30 + 2*5 = 42.
Box   := fn(T : type) -> type { return struct { v : T } }
mkbox := fn(T : type, x : T) -> Box(T) { return Box(T)(v = x) }
unbox := fn(T : type, b : Box(T)) -> T { return b.v }

main := fn() -> u64 {
  s := mkbox(Option(u64), Option(u64).Some(2))
  n := mkbox(Option(u64), Option(u64).None)
  mut r : u64 = 0
  ## the Some instantiation — the payload must survive the wrap
  match s.v {
    Option::Some(x) => { r = r + x }
    Option::None => { r = r + 100 }
  }
  ## the None instantiation — a DIFFERENT arm of the same two-arm match
  match n.v {
    Option::Some(x) => { r = r + x }
    Option::None => { r = r + 30 }
  }
  ## the wrapped enum back out through a `Box(T)` param, at a generic-INSTANCE type argument
  o := unbox(Option(u64), s)
  match o {
    Option::Some(x) => { r = r + x * 5 }
    Option::None => { r = r + 100 }
  }
  r
}
