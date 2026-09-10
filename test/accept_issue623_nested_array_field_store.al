## Issue #623 — a store through a field path with TWO owners must reach the element.
## `p_stmt`/`stmt_starts` recognised `v.field[i] =` only with the `[` immediately after the first
## field, so `outer.leaf.arr[0] = 42` matched no assignment form at all: the line fell to the
## trailing-expression path and the store was emitted nowhere. Measured on the parent, the minimal
## single-store form exited 0 with the pre-store value 10 on AArch64, RISC-V64 and Wasm and printed
## no diagnostic; this two-store fixture trapped there instead (133/133/134), because the fallback
## also mis-parses the second line. x86_64 declines the fixed-array carrier here at build time — a
## separate, fail-loud lowering gap that the per-file corpus row records — so the cross-backend
## runners carry this row.
## Both locals are bound before the first store on purpose: an indexed store followed by a LATER
## struct local traps on Wasm for a single owner and for a bare local array too, on the parent as
## well, and that unrelated defect must not be smuggled into this row.
Leaf := struct { arr : [u64; 2] }
Outer := struct { leaf : Leaf }
Mid := struct { leaf : Leaf }
Deep := struct { mid : Mid }

main := fn() -> u64 {
  mut outer := Outer(leaf = Leaf(arr = [10, 20]))
  mut deep := Deep(mid = Mid(leaf = Leaf(arr = [1, 2])))
  outer.leaf.arr[0] = 42
  if outer.leaf.arr[0] != 42 { return 7 }
  if outer.leaf.arr[1] != 20 { return 8 }
  deep.mid.leaf.arr[1] = 30
  if deep.mid.leaf.arr[1] != 30 { return 9 }
  if deep.mid.leaf.arr[0] != 1 { return 10 }
  outer.leaf.arr[0]
}
