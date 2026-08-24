## e2e (COMPTIME-FOR UNROLL — the metaprogramming core of the comptime evaluator; the last piece of
## item #3). `comptime for f in typeinfo(T).fields { … }` is UNROLLED over the instance struct's
## fields (in a mono instance where T is concrete): for each field it emits the body with the loop
## var bound, resolving `v.(f)` (CompField → the member access) and `f.type` (the member's type, a
## generic TYPE-arg → the recursive `hash(<fieldtype>, …)` routes to the concrete instance). The
## mono worklist instantiates `hash__<fieldtype>` per field. This is exactly `base/derive`'s
## structural `hash`: a STRUCT folds its field hashes, a SCALAR hashes its own value. Here
## `hash(Pt, Pt{40, 2})` = hash(u64, 40) + hash(u64, 2) = 40 + 2 = 42.
Pt := struct { x : u64, y : u64 }
hash := fn(T : type, v : T) -> u64 {
  comptime if (match typeinfo(T) { Struct(_) => true; _ => false }) {
    mut h : u64 = 0
    comptime for f in typeinfo(T).fields { h = h + hash(f.type, v.(f)) }
    return h
  } else {
    return u64(v)
  }
}
main := fn() -> u64 {
  hash(Pt, Pt(x = 40, y = 2))
}
