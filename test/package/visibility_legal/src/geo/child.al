## `geo::child` — a DESCENDANT of `geo`. §3: "a descendant module sees its ancestors' non-`pub`
## items", so every reference below is legal without `pub` on the target — bare and qualified alike,
## for a function, a constant and a type. Re-exporting them would NOT be (§4.3, a separate fixture).
pub from_ancestor := fn() -> u64 {
  q := geo::Priv(v = geo::PRIV_C)
  return geo::priv_helper() + q.v + geo::take_priv(q)
}
## a `pub` re-export of a `pub` item is legal (§4.3 admits exactly this)
pub re_answer := geo::answer
