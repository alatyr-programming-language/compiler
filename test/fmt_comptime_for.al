Pt := struct {
  x : u64,
  y : u64,
}
sumfields := fn(T : type, v : T) -> u64 {
  s := 0
  comptime for f in typeinfo(T).fields {
    s = s + v.(f)
  }
  return s
}
main := fn() -> u64 {
  return sumfields(Pt, Pt(x = 40, y = 2))
}
