E := enum { A(u64), B(u64) }

sum := fn(T : type, v : T) -> u64 {
  mut out := 0
  match v {
    comptime for k in typeinfo(T).variants {
      T.(k)(p) => {
        mut local := u64(p)
        local = local + 1
        out = local - 1
      }
    }
    _ => {
      out = 99
    }
  }
  return out
}

main := fn() -> u64 {
  return sum(E, E.B(7))
}
