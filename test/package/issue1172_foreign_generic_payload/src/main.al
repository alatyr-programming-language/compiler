V := enum {
  Null,
  Arr(m::G(u64)),
}

walk := fn(v : V) -> u64 {
  match v {
    V.Null => {
      1
    }
    V.Arr(xs) => {
      xs.a + xs.b + xs.c + xs.d
    }
  }
}

main := fn() -> u64 {
  g := m::mk()
  walk(V.Arr(g))
}
