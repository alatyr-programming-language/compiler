## ROADMAP §1/§4: a generic fn returning its type parameter (`id(T, v) -> T`) applied to a STRUCT.
## Previously the instance id__P didn't set ret_struct for the substituted T→P, so `return v` (a
## by-ref struct param) returned the pointer, and the caller bound p as a scalar (took only %rax).
## Now: emit_fn resolves the effective (substituted) return type -> ret_struct; emit_struct_value's
## Var arm dereferences a by-ref struct param into the return registers; and the caller binds
## `p := id(P, …)` as the struct (gen_ret_struct_span). Works for a plain struct AND one with an
## enum field (which also exercises the enum-field layout).
Col := enum { R, G(u64) }
P := struct { x : u64, y : u64 }
S := struct { c : Col, n : u64 }
id := fn(T : type, v : T) -> T { return v }
main := fn() -> u64 {
  p := id(P, P(x = 30, y = 1))
  s := id(S, S(c = Col.G(9), n = 2))
  return p.x + p.y + match s.c { Col::R => { 0 }; Col::G(k) => { k } } + s.n
}
