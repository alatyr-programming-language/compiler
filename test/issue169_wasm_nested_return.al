## Regression for #169: a nested standard-byte aggregate returned by value must not become a valid
## but differently-laid-out WASM address. AArch64/RV64 already fence this shape; WASM must retain the
## same fail-loud outcome.

Leaf := struct { b : u8, c : u8 }
Outer := struct { a : u8, inner : Leaf }

make_outer := fn() -> Outer { Outer(a = 2, inner = Leaf(b = 1, c = 2)) }

main := fn() -> u64 {
  r := make_outer()
  u64(r.a) * 10 + u64(r.inner.b) + u64(r.inner.c)
}
