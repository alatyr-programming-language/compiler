## Modules §3 — a SIBLING may not name `geo`'s non-`pub` enum type, literal included.
main := fn() -> u64 {
  t := geo::PrivTag.hi
  match t {
    geo::PrivTag::lo => { 1 }
    geo::PrivTag::hi => { 42 }
  }
}
