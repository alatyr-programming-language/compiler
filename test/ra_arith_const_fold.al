## e2e — the scalar-IR arithmetic constant-folding slice. Unchecked native scalar arithmetic has no
## overflow guard, so the local `mov; add|sub|imul` shape may become one immediate `mov`. The checked
## guard-preservation case lives in the allocator selftest and the existing `ra_checked_trap` e2e.
main := fn() -> u64 {
  a := unchecked { 40 + 2 }
  b := unchecked { 40 - 2 }
  c := unchecked { 6 * 7 }
  a + b - c + 4
}
