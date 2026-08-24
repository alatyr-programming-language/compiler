## e2e — NESTED generic struct type-arg tracking (CT). A generic `Box(T)` instantiated with
## an AGGREGATE type-arg `Pair(u64)` (a multi-field struct): `c := Box(Pair(u64))(v = Pair(u64)(a=40, b=2))`
## must size + type `c.v` as the concrete `Pair(u64)` (2 words) so `c.v.a + c.v.b` = 40 + 2 = 42. Before
## the fix the nested generic instance lost its type-arg (v mis-sized as a bare param T = 1 word) and
## `c.v.a` read 0 / `c.v.b` was lost. Single-level generic (`Box(u64)`) and the concrete equivalent both
## already worked; this pins the nested multi-field generic case.
Pair := fn(T : type) -> type { return struct { a : T, b : T } }
Box := fn(T : type) -> type { return struct { v : T } }
main := fn() -> u64 {
  c := Box(Pair(u64))(v = Pair(u64)(a = 40, b = 2))
  c.v.a + c.v.b
}
