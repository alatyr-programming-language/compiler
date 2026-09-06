## e2e (#472) — the LOUD face of the SAME defect. Same collapse, different arities: each call site
## selected its OWN declaration, so BOTH bodies were emitted, and both carried the identical
## `.globl <module>__f__<typetag>` — the assembler refused the file with
## `symbol ... is already defined` and the program never ran. Arity is exactly what decides whether
## this defect is silent (`issue472_generic_overload_same_arity`) or loud: it is one root cause.
##
## Parent verdict: build rc=13, `as` rejected the emitted assembly. Fixed verdict: 42.
## Modules §6.7 (linker-symbol uniqueness). x86_64 default build path; the three cross backends
## refuse the whole shape through `lower_layout::gen_call_ok`'s fence (see the same-arity fixture).

A := struct { x : u64 }
B := struct { p : u64, y : u64 }

f := fn(T : type, a : A, k : u64) -> u64 { a.x + k }
f := fn(T : type, b : B) -> u64 { b.y }

## a THREE-member set, mixing both discriminators at once: two members share an arity (so only the
## value signature separates them) while the third differs in arity.
g := fn(T : type, a : A) -> u64 { a.x }
g := fn(T : type, b : B) -> u64 { b.y }
g := fn(T : type, a : A, b : B) -> u64 { a.x + b.y }

main := fn() -> u64 {
  if f(u64, A(x = 1), 2) != 3 { return 10 }
  if f(u64, B(p = 7, y = 42)) != 42 { return 11 }
  if g(u64, A(x = 1)) != 1 { return 12 }
  if g(u64, B(p = 7, y = 42)) != 42 { return 13 }
  if g(u64, A(x = 1), B(p = 7, y = 41)) != 42 { return 14 }
  42
}
