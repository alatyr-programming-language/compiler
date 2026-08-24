## e2e — Types §9.4 DEEPER fixed-array read: a LOCAL struct-element array element, an intermediate
## STRUCT field, then a SCALAR leaf (`xs[i].inner.x`, the combined-offset element→field→leaf seam,
## `resolve_deep_idx_field` in lower). `pad` shifts `inner` to a NON-zero word offset so the combined
## offset (element base + agg-field offset + leaf offset) is exercised, not just offset 0. Reached via a
## whole-element assign (the reads are all definitely-assigned). Was a SILENT MISCOMPILE (each deep read
## fell to the `pushq $0` default → 0) before the combined-offset read seam; a locking guard for it.
## The total is kept BELOW 126: this fixture is swept on every backend, and WASI `proc_exit` only accepts
## a status in [0,126) — at the old 135 wasmtime aborted with a host error, which the wasm sweep could not
## tell apart from a failure without a special case. Distinct non-zero values at distinct offsets are what
## the guard needs, not a large sum.
Leaf := struct { x : u64, y : u64 }
Cell := struct { pad : u64, inner : Leaf, z : u64 }
main := fn() -> u64 {
  mut xs : [Cell; 3]
  xs[0] = Cell(pad = 99, inner = Leaf(x = 5, y = 30), z = 7)
  xs[2] = Cell(pad = 1, inner = Leaf(x = 11, y = 20), z = 3)
  ## 5 + 30 + 7 (element 0) + 11 + 20 + 3 (element 2) = 76; xs[1] stays untouched.
  u64(xs[0].inner.x + xs[0].inner.y + xs[0].z + xs[2].inner.x + xs[2].inner.y + xs[2].z)
}
