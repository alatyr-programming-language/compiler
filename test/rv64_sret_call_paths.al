## e2e / rv64 — the complete wide-SRET call boundary: a bare call gets a discard destination, a direct
## callee with eight real integer args shifts a0 and spills the last arg, a generic `-> T` instance gets
## the same hidden result pointer, and a generic call can receive a wide-SRET call as an aggregate argument.
## The two final calls are deliberately bare statements. 8 + 9 + 8 + 42 = 67.

S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

direct := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64) -> S9 {
  return S9(a = a, b = b, c = c, d = d, e = e, f = f, g = g, h = h, i = 9)
}

generic_make := fn(T : type, a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64) -> T {
  return S9(a = a, b = b, c = c, d = d, e = e, f = f, g = g, h = h, i = 9)
}

identity := fn(T : type, v : T) -> T { return v }
sink := fn() { direct(1, 2, 3, 4, 5, 6, 7, 8) }

main := fn() -> u64 {
  d := direct(1, 2, 3, 4, 5, 6, 7, 8)
  n := identity(S9, direct(4, 5, 6, 7, 8, 9, 10, 11))
  g := generic_make(S9, 1, 2, 3, 4, 5, 6, 7, 8)
  direct(1, 2, 3, 4, 5, 6, 7, 8)
  generic_make(S9, 1, 2, 3, 4, 5, 6, 7, 8)
  sink()
  return d.h + n.i + g.h + 42
}
