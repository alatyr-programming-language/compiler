## e2e — a bare SCALAR TYPE NAME as a comptime type-builtin argument (`size(u64)`, `align(u64)`,
## `size(u8)`): the argument is a TYPE, not an unbound value (Types §6.4/§6.5 — was "unbound name").
## Values: size(u64)=8, align(u64)=8, size(u8)=1, align(u8)=1. Returns 42 iff all match.
main := fn() -> u64 {
  s := size(u64)
  a := align(u64)
  t := size(u8)
  u := align(u8)
  ok := (s == 8) and (a == 8) and (t == 1) and (u == 1)
  if ok { 42 } else { 1 }
}
