pub G := fn(T : type) -> type { struct { a : T, b : T, c : T, d : T } }

pub mk := fn() -> G(u64) {
  G(u64)(a = 3, b = 4, c = 5, d = 30)
}
