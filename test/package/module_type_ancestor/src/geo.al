## `geo`s OWN items. NONE is `pub`: §3 down-tree privacy is exactly what makes them nameable from
## `geo::child` and `geo::deep::leaf` without exposing them upward.
Box := struct { a : u64 }                       ## size 8
U := union { n(u64) }                           ## size 8
E := enum { Hit(u64), Miss }                    ## size 16 (tag + widest payload)
Handle := Box                                   ## a type ALIAS to the struct above
Cell := fn(T : type) -> type { return struct { v : T, tail : u64 } }
always_ok := fn(v : u64) -> bool { return v != 0 }
Nz := @require(always_ok) u64                   ## the @require CONTRACT: which predicate runs
