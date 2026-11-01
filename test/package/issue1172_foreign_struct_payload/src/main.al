V := enum {
  Null,
  Arr(m::S),
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
  walk(V.Arr(m::S(a = 3, b = 4, c = 5, d = 30)))
}
## expect: reject
