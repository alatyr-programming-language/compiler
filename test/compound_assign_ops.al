## Compound-assignment for all four arithmetic operators (spec §10 compound-assign). Only += existed;
## -= *= /= are added (lexer kinds 41/44/45 + the compound_op desugar). Field form too (a.v -= n).
Acc := struct { v : u64 }
main := fn() -> u64 {
  mut x := 100
  x -= 50
  x *= 3
  x /= 2
  x += 1
  mut a := Acc(v = 84)
  a.v -= 42
  x = a.v
  x
}
