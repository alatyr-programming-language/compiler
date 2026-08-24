## `geo` — the module with both a public surface and private internals.

## NON-`pub`: visible to `geo` and to every module NESTED WITHIN it (§3), i.e. to `geo::child`.
priv_helper := fn() -> u64 { 3 }
PRIV_C := 4
Priv := struct { v : u64 }

## `pub`: exposed one level upward, so the root and its other children may name these (§3).
pub Pt := struct { x : u64, y : u64 }
pub Tag := enum { lo, hi }
pub PUB_C := 10
pub answer := fn() -> u64 { priv_helper() + PRIV_C }
pub bump := fn(p : ptr(Pt)) -> u64 { deref(p).x + deref(p).y }
pub widen := fn(T : type, v : T) -> u64 { u64(v) + 1 }
pub tag_code := fn(t : Tag) -> u64 {
  match t {
    Tag::lo => { 1 }
    Tag::hi => { 2 }
  }
}
pub take_priv := fn(p : Priv) -> u64 { p.v }
