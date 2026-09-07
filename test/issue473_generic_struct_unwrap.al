## e2e — Issue #473 / Stdlib appendix §2.3 + §4.2, Types §4: `unwrap(T, Option(T).Some(v))` must
## yield the WHOLE `v` when `T` is an instantiation of a GENERIC struct. The generic enum-value
## param `self : Option(T)` is sized and materialized from the SUBSTITUTED instance span; the
## substitution's "is this type-arg a wide struct?" test looked the type-arg up by its FULL span,
## so a generic instance (`Pair(u64, u64)`) missed its `Pair` decl, no substituted span was
## synthesized, and the param kept the un-substituted `Option(T)` layout: ONE payload word.
##
## Failure-first on parent 8b422be (x86_64, default build path): this program builds rc=0 and exits
## 13 — `p.val` reads back as 0 (`Tri`'s third field reads back as the FIRST field's value, and the
## `Entry(K, V)` walk in the sibling fixture reads the key in place of the value). Each field is
## checked on its own with a DISTINCT code below 126 that says WHICH wrong shape was observed —
## zero, a neighbouring field's value, or other garbage — and nothing is summed into one total.
##
## The two controls that isolate the defect to the `unwrap` path are here on purpose and must stay
## green in both directions: a `match` over the SAME `Option` value (already correct on the parent)
## and the same shapes over a NON-generic struct (already correct on the parent).
Pair := fn(K : type, V : type) -> type { struct { key : K, val : V } }
Tri := fn(A : type, B : type, C : type) -> type { struct { a : A, b : B, c : C } }
Rec := struct { key : u64, val : u64 }

main := fn() -> u64 {
  ## ---- 2-field GENERIC payload, prefix `unwrap` --------------------------------------------
  o1 := Option(Pair(u64, u64)).Some(Pair(u64, u64)(key = 5, val = 9))
  p := unwrap(Pair(u64, u64), o1)
  if p.key != 5 {
    if p.key == 0 { return 10 }
    if p.key == 9 { return 11 }
    return 12
  }
  if p.val != 9 {
    if p.val == 0 { return 13 }
    if p.val == 5 { return 14 }
    return 15
  }

  ## ---- 3-field GENERIC payload: "every field after the first" needs THREE ------------------
  o2 := Option(Tri(u64, u64, u64)).Some(Tri(u64, u64, u64)(a = 7, b = 11, c = 13))
  t := unwrap(Tri(u64, u64, u64), o2)
  if t.a != 7 {
    if t.a == 0 { return 20 }
    if t.a == 11 { return 21 }
    if t.a == 13 { return 22 }
    return 23
  }
  if t.b != 11 {
    if t.b == 0 { return 24 }
    if t.b == 7 { return 25 }
    if t.b == 13 { return 26 }
    return 27
  }
  if t.c != 13 {
    if t.c == 0 { return 28 }
    if t.c == 7 { return 29 }
    if t.c == 11 { return 30 }
    return 31
  }

  ## ---- the same generic payload through `expect` (the same param substitution) -------------
  o3 := Option(Tri(u64, u64, u64)).Some(Tri(u64, u64, u64)(a = 7, b = 11, c = 13))
  x := expect(Tri(u64, u64, u64), o3, "should be Some")
  if x.a != 7 {
    if x.a == 0 { return 40 }
    if x.a == 11 { return 41 }
    if x.a == 13 { return 42 }
    return 43
  }
  if x.b != 11 {
    if x.b == 0 { return 44 }
    if x.b == 7 { return 45 }
    if x.b == 13 { return 46 }
    return 47
  }
  if x.c != 13 {
    if x.c == 0 { return 48 }
    if x.c == 7 { return 49 }
    if x.c == 11 { return 50 }
    return 51
  }

  ## ---- CONTROL A: `match` over the SAME Option shape — correct on the parent, must stay ----
  o4 := Option(Tri(u64, u64, u64)).Some(Tri(u64, u64, u64)(a = 7, b = 11, c = 13))
  match o4 {
    Option::Some(m) => {
      if m.a != 7 {
        if m.a == 0 { return 60 }
        if m.a == 11 { return 61 }
        if m.a == 13 { return 62 }
        return 63
      }
      if m.b != 11 {
        if m.b == 0 { return 64 }
        if m.b == 7 { return 65 }
        if m.b == 13 { return 66 }
        return 67
      }
      if m.c != 13 {
        if m.c == 0 { return 68 }
        if m.c == 7 { return 69 }
        if m.c == 11 { return 70 }
        return 71
      }
    }
    Option::None => { return 72 }
  }

  ## ---- CONTROL B: the NON-generic struct of the same shape — correct on the parent ---------
  o5 := Option(Rec).Some(Rec(key = 5, val = 9))
  r := unwrap(Rec, o5)
  if r.key != 5 {
    if r.key == 0 { return 80 }
    if r.key == 9 { return 81 }
    return 82
  }
  if r.val != 9 {
    if r.val == 0 { return 83 }
    if r.val == 5 { return 84 }
    return 85
  }

  ## ---- a `None` over a generic payload still takes the absent arm --------------------------
  o6 := Option(Pair(u64, u64)).None
  if is_some(Pair(u64, u64), o6) { return 90 }
  if is_none(Pair(u64, u64), o6) == false { return 91 }

  100 - 58
}
