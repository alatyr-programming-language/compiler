## fmt fixture — a GENERIC TYPE FUNCTION and a generic-INSTANCE construction (Types §9.2). Two wrong
## renders, both of which left source that no longer parsed (so the SECOND fmt pass died too):
##   • `Either := fn(A : type, B : type) -> type { return enum { L(A), R(B) } }` is normalized by the
##     parser into a generic ENUM decl whose fields are the variants. Rebuilding it canonically
##     spliced the two halves together —
##       `Either(A : type, B : type) := fn(A : type, B : type) -> type { L(A), R(B), }`
##     — which is not a declaration in any form. fmt now checks that the recovered `:=`-to-`{` head
##     really ends in `struct`/`enum`/`union` and, when it does not, copies the whole decl verbatim.
##   • `Either(A, B).L(a)` keeps only the BASE name span in its `EnumLit`, so the type-argument group
##     was dropped and `Either.L(a)` named no type. Recovered verbatim: the only thing that can
##     directly follow an enum-name span is that group (a payload comes after the `.V`).
## Returns 42.
Either := fn(A : type, B : type) -> type { return enum { L(A), R(B) } }

pick := fn(A : type, B : type, sel : u64, a : A, b : B) -> Either(A, B) {
  if sel == 0 { return Either(A, B).L(a) }
  return Either(A, B).R(b)
}

main := fn() -> u64 {
  t := pick(u64, u64, 1, 10, 12)
  match t {
    L(x) => { return x }
    R(y) => { return y + 30 }
  }
}
