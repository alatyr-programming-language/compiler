## e2e / issue #864 — a scalar module GLOBAL passed as a bare call argument is the global's value,
## whatever the calling function's FIRST parameter is.
##
## The x86_64 argument lowering resolved a bare-name argument through the frame-slot table. A global
## has no frame slot, and the lookup answered the unbound sentinel, entry 0: the calling function's
## first parameter. When that parameter was by-reference (an `Option(ptr(T))`, a struct, an enum, a
## `str`) the argument was passed as that parameter's address, so `eq2(7, 1, G1, G2)` compared against
## the first parameter's pointer and answered false. A scalar first parameter hid it (the sentinel then
## fell to the value path, which resolves the global correctly).
##
## Covered: an `Option(ptr(T))`, struct and enum first parameter (a `str` one is
## `issue864_global_arg_str`, x86_64 only: the twins have no `str` argument); the global as the 1st, 4th
## and 7th (stack) argument; inside a nested call's argument; in a binary operand; `u8`, `u32` and
## `bool` globals; a module constant; a local shadowing a global's name still passes the local; the controls with the
## by-reference parameter second and with a scalar first. The `Option` arguments are `None`: the
## defect is decided by the parameter's shape, not by the value it holds, and the twins have no `ptr(mut x)`.
##
## 42 means every case held. Each miss owns its own code from 100 up.
mut G1 : usize = 0
mut G2 : usize = 0
mut GB : u8 = 0
mut GW : u32 = 0
mut GT : bool = false
KC : usize = 7

P := struct { v : usize }
K := enum { A, B(usize) }

eq2 := fn(a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool { a_s == b_s and a_n == b_n }
id := fn(x : usize) -> usize { x }
sum8 := fn(a : usize, b : usize, c : usize, d : usize, e : usize, f : usize, g : usize, h : usize) -> usize { a + b * 2 + c + d + e + f + g * 100 + h }
is8 := fn(x : u8) -> bool { x == 200 }
is32 := fn(x : u32) -> bool { x == 70000 }
truth := fn(x : bool) -> bool { x }

f_opt_first := fn(h : Option(ptr(mut P)), k : usize) -> usize { if eq2(7, 1, G1, G2) { 1 } else { 0 } }
f_opt_second := fn(k : usize, h : Option(ptr(mut P))) -> usize { if eq2(7, 1, G1, G2) { 1 } else { 0 } }
f_scalar_first := fn(h : usize, k : usize) -> usize { if eq2(7, 1, G1, G2) { 1 } else { 0 } }
f_struct_first := fn(s : P, k : usize) -> usize { if eq2(7, 1, G1, G2) { 5 } else { 0 } }
f_enum_first := fn(e : K, k : usize) -> usize { if eq2(7, 1, G1, G2) { 1 } else { 0 } }
f_first_arg := fn(h : Option(ptr(mut P))) -> usize { if eq2(G1, G2, 7, 1) { 1 } else { 0 } }
f_stack_arg := fn(h : Option(ptr(mut P))) -> usize { sum8(G2, G1, 0, 0, 0, 0, G2, G1) }
f_nested := fn(h : Option(ptr(mut P))) -> usize { if eq2(7, 1, id(G1), id(id(G2))) { 1 } else { 0 } }
f_binop := fn(h : Option(ptr(mut P))) -> usize { if eq2(8, 2, G1 + 1, G2 * 2) { 1 } else { 0 } }
f_narrow := fn(h : Option(ptr(mut P))) -> usize {
  mut r : usize = 0
  if is8(GB) { r += 1 }
  if is32(GW) { r += 2 }
  if truth(GT) { r += 4 }
  r
}
f_const := fn(h : Option(ptr(mut P))) -> usize { if eq2(7, 1, KC, G2) { 1 } else { 0 } }
f_shadow := fn(h : Option(ptr(mut P))) -> usize {
  G1 := 3
  if eq2(3, 1, G1, G2) { 1 } else { 0 }
}

main := fn() -> u64 {
  G1 = 7
  G2 = 1
  GB = 200
  GW = 70000
  GT = true
  p := P(v = 5)
  if f_opt_first(Option.None, 1) != 1 { return 100 }
  if f_opt_second(1, Option.None) != 1 { return 101 }
  if f_scalar_first(5, 1) != 1 { return 102 }
  if f_struct_first(p, 1) != 5 { return 103 }
  if f_enum_first(K.B(9), 1) != 1 { return 104 }
  if f_first_arg(Option.None) != 1 { return 106 }
  ## 1 + 7*2 + 0 + 0 + 0 + 0 + 1*100 + 7
  if f_stack_arg(Option.None) != 122 { return 107 }
  if f_nested(Option.None) != 1 { return 108 }
  if f_binop(Option.None) != 1 { return 109 }
  if f_narrow(Option.None) != 7 { return 110 }
  if f_shadow(Option.None) != 1 { return 111 }
  if f_const(Option.None) != 1 { return 112 }
  return 42
}
