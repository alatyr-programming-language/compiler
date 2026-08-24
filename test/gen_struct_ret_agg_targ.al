## e2e — Types §9.4: a GENERIC fn whose declared return type is a GENERIC-STRUCT APPLICATION over its
## own type parameter (`mkbox := fn(T : type, x : T) -> Box(T)`), instantiated at an AGGREGATE type
## argument. `Box(T)`'s field `v : T` sizes as ONE SCALAR WORD until the application is resolved to the
## instantiation (`Box(P)`), and the raw `Box(T)` is what BOTH sides read: the callee moved one word of
## the returned aggregate and the caller's binding reserved one word. Every field past word 0 came back
## 0 — a SILENT truncated struct that compiled and ran.
##
## Covers, in one program: the RETURN of a generic-struct application at a struct type-arg
## (`mkbox(P, p)`); the same value read back through a generic-struct PARAM (`unbox(P, bx)`, whose
## `b : Box(T)` param must bind the instantiated width); a generic struct with a SECOND, concrete field
## (`Pair(T) { v : T, tag : u64 }` — the aggregate field must not displace `tag`); and a NESTED
## instantiation at depth 2 (`Box(Box(u64))`, whose 1-word aggregate field slipped past the width gate
## and returned the field's ADDRESS instead of its value).
##
## The isolating controls that were ALREADY sound and must stay so: the identical literal written at
## the CALL SITE (`Box(P)(v = p)`), and a scalar type-arg (`Box(u64)`), both below.
## Returns (10+2) + (10+2) + (10+2+3) + 3 = 42.
Box   := fn(T : type) -> type { return struct { v : T } }
Pair  := fn(T : type) -> type { return struct { v : T, tag : u64 } }
P     := struct { a : u64, b : u64 }

mkbox  := fn(T : type, x : T) -> Box(T) { return Box(T)(v = x) }
unbox  := fn(T : type, b : Box(T)) -> T { return b.v }
mkpair := fn(T : type, x : T) -> Pair(T) { return Pair(T)(v = x, tag = 3) }

main := fn() -> u64 {
  p  := P(a = 10, b = 2)
  bx := mkbox(P, p)                  ## generic return of `Box(T)` at an aggregate type-arg
  q  := unbox(P, bx)                 ## the same value back OUT through a `Box(T)` param
  pr := mkpair(P, p)                 ## a second, CONCRETE field after the substituted one
  in0 := Box(u64)(v = 3)             ## the call-site literal at a SCALAR type-arg (control)
  bb := mkbox(Box(u64), in0)         ## depth 2: `Box(Box(u64))`, a 1-word aggregate field
  bx.v.a + bx.v.b + q.a + q.b + pr.v.a + pr.v.b + pr.tag + bb.v.v
}
