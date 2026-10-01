## Issue #791 — an aggregate FIELD read straight off a struct-returning CALL (`f(mk().kind)`). The call
## result has no frame home. Passed as an argument, the field's first WORD was handed to the callee as
## its by-reference block pointer, so the parent built this cleanly and it crashed with SIGSEGV (rc 139)
## at the first check. Returned by value (`fn() -> K { mk().kind }`), it was the null enum or struct (1
## and 0 on the parent). The forms covered: an enum field, a payload enum field, and a nested struct
## field, each as an argument and returned by value; two such arguments in one expression; and an enum
## field of a WIDE (hidden-pointer) struct result as an argument. Each check has its own exit code.
K := enum { KA, KB, KC }
P := enum { PN, PV(u64, u64) }
S := struct { x : u64, y : u64 }
T := struct { a : u64, kind : K, b : u64 }
U := struct { kind : K, pk : P, s : S }
Wd := struct { a : u64, kind : K, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64 }
mk := fn() -> T { T(a = 1, kind = K.KC, b = 2) }
mu := fn() -> U { U(kind = K.KB, pk = P.PV(30, 12), s = S(x = 40, y = 2)) }
mw := fn() -> Wd { Wd(a = 1, kind = K.KC, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7) }
is_c := fn(k : K) -> u64 { match k { K::KA => { 1 } K::KB => { 2 } K::KC => { 42 } } }
pv := fn(p : P) -> u64 { match p { P::PN => { 1 } P::PV(a, b) => { a + b } } }
sx := fn(s : S) -> u64 { s.x + s.y }
gk := fn() -> K { mk().kind }
gp := fn() -> P { mu().pk }
gs := fn() -> S { mu().s }
main := fn() -> u64 {
  if is_c(mk().kind) != 42 { return 2 }
  if pv(mu().pk) != 42 { return 3 }
  if sx(mu().s) != 42 { return 4 }
  if is_c(gk()) != 42 { return 5 }
  if pv(gp()) != 42 { return 6 }
  if sx(gs()) != 42 { return 7 }
  if pv(mu().pk) + is_c(mk().kind) != 84 { return 8 }
  if is_c(mw().kind) != 42 { return 9 }
  42
}
