## e2e — the scalar-IR arithmetic constant-folding slice. Unchecked native scalar arithmetic has no
## overflow guard, so the local `mov; add|sub|imul` shape may become one immediate `mov`. The checked
## guard-preservation case lives in the allocator selftest and the existing `ra_checked_trap` e2e.
main := fn() -> u64 {
  a : u64 = unchecked { 40 + 2 }
  b : u64 = unchecked { 40 - 2 }
  c : u64 = unchecked { 6 * 7 }
  a + b - c + 4
}
## expect(x86_64): run 42
