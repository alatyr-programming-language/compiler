## e2e / issue #864 — the `str` twin of `issue864_global_arg`: a scalar module GLOBAL passed as a bare
## call argument inside a function whose FIRST parameter is a by-reference `str`.
##
## The argument lowering resolved the global's name through the frame-slot table, which has no entry
## for a global, and the unbound sentinel was entry 0 — here the `str` parameter. The argument was then
## passed as that `str`'s block address instead of the global's value. x86_64 only: the twins do not
## lower a `str` argument.
##
## 42 means every case held. Each miss owns its own code from 100 up.
mut G1 : usize = 0
mut G2 : usize = 0
mut GB : u8 = 0

eq2 := fn(a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool { a_s == b_s and a_n == b_n }
is8 := fn(x : u8) -> bool { x == 200 }

f_str_first := fn(t : str, k : usize) -> usize { if eq2(7, 1, G1, G2) { t.len } else { 0 } }
f_str_second := fn(k : usize, t : str) -> usize { if eq2(7, 1, G1, G2) { t.len } else { 0 } }
f_str_byte := fn(t : str) -> usize { if is8(GB) { t.len } else { 0 } }

main := fn() -> u64 {
  G1 = 7
  G2 = 1
  GB = 200
  if f_str_first("abc", 1) != 3 { return 100 }
  if f_str_second(1, "abcd") != 4 { return 101 }
  if f_str_byte("ab") != 2 { return 102 }
  return 42
}
