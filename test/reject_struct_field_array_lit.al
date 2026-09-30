## #726 / Types §9.4 — an ARRAY literal is an N-element aggregate, and a struct field declared `u64`
## is one word: no conversion-lattice class relates them. The parent accepted this and returned 40,
## the array's first word, because `check_expr`'s `ArrayLit` arm, which types the literal, had never
## run and the struct-literal field compare saw UNKNOWN. An array-typed field (`a : [u64; 2]`) accepts
## the same literal.
S := struct { a : u64 }

main := fn() -> u64 {
  s := S(a = [40, 2])
  return s.a
}
