## TYP-8 check/build parity: named struct construction is by field name even
## when the source order differs and the fields have different types. Without
## the struct-order table, check sees the string as x : u64 and rejects a valid
## program that build parses and lowers correctly.
K := 0
S := struct { x : u64, y : str }
main := fn() -> u64 {
  s := S(y = "ok", x = 42)
  if s.x != 42 { return 1 }
  if s.y.len() != 2 { return 2 }
  42
}
