## e2e (#1473) - `u16` is a kernel integer (Types §3), so an annotated `u16` binding records its type
## and a later out-of-range write is judged against it: `x = 70000` is outside 0..65535 and is refused
## at its line. Before #1471 `u16` was missing from `resolve_ty`'s list, the binding recorded no type,
## and the write was accepted silently. The in-range writes above it, the upper bound AT its edge
## included, stay accepted.
## expect: reject "type mismatch" "at line 10"
main := fn() -> u64 {
  mut x : u16 = 1
  x = 65535
  x = 70000
  u64(x)
}
