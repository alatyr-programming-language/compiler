P := struct { x : u64 }
main := fn() -> u64 {
  mut xs : [P; 2] = [P(x = 1), P(x = 2)]
  s := xs[0..2]
  s[0] = "text"
  0
}
