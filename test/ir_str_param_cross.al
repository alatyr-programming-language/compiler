## e2e — #1576: a `str` crosses a call between the shared IR and the legacy x86_64 emitter, in both
## directions, as five parameters, beside word parameters, as a result, and as the parameter of a
## function value (a `str` RESULT through one is wrong on the legacy side alone, #1669). `*_lg` hold a
## float literal the IR does not build, so the legacy emitter emits them; `*_ir` and `main` are IR-built
## on x86_64. On both sides a `str` PARAMETER is one word, the address of its `{ptr, len}` pair (Types
## §7; Stdlib appendix §3.6), so five of them take five of the six argument registers and none goes on
## the stack; a `str` RESULT comes back as the pair in two registers. The bytes are at stride 1 on both
## sides, so the crossing agrees. An argument past the six registers never crosses: the x86_64 selector
## refuses a call or a function that would pass one, so both ends stay legacy, and this fixture does not
## exercise that boundary. On aarch64,
## riscv64 and wasm `ir::sig_pins_legacy` keeps every function with a `str` in its signature, and every
## caller of one, legacy, so nothing crosses there (their legacy emitters build no `str`, #1184).
## Exit 42 = all held; otherwise 100 + the mask of `drv_ir`'s failed checks (101..107), or 110 + the
## mask of `drv_lg`'s (111..125). Parent `774ba852` built every function here with the legacy
## emitter (x86_64 42, aarch64 and riscv64 133, wasm 134).
five_ir := fn(a : str, b : str, c : str, d : str, e : str) -> usize {
  a.len + b.len * 2 + c.len * 3 + d.len * 4 + e.len * 5 + usize(e[1]) - 98
}
five_lg := fn(a : str, b : str, c : str, d : str, e : str) -> usize {
  fz := 1.5
  a.len + b.len * 2 + c.len * 3 + d.len * 4 + e.len * 5 + usize(e[1]) - 98
}
mix_ir := fn(x : u64, a : str, y : u8, b : str, z : i32) -> usize {
  usize(x) + a.len + usize(y) + usize(b[0]) - 97 + b.len + usize(z)
}
mix_lg := fn(x : u64, a : str, y : u8, b : str, z : i32) -> usize {
  fz := 1.5
  usize(x) + a.len + usize(y) + usize(b[0]) - 97 + b.len + usize(z)
}
pick_ir := fn(s : str, t : str, n : usize) -> str {
  if n > 2 { return s }
  t
}
pick_lg := fn(s : str, t : str, n : usize) -> str {
  fz := 1.5
  if n > 2 { s } else { t }
}
drv_lg := fn() -> u64 {
  fz := 1.5
  mut m : u64 = 0
  if five_ir("a", "bb", "c", "dd", "abc") != 31 { m = m + 1 }
  if mix_ir(10, "ab", 3, "cde", 20) != 40 { m = m + 2 }
  r := pick_ir("abcd", "q", 3)
  if r.len != 4 or r[3] != 100 { m = m + 4 }
  h : fn(u64, str, u8, str, i32) -> usize = mix_ir
  if h(1, "abc", 2, "bc", 3) != 12 { m = m + 8 }
  m
}
drv_ir := fn() -> u64 {
  mut m : u64 = 0
  if five_lg("a", "bb", "c", "dd", "abc") != 31 { m = m + 1 }
  if mix_lg(10, "ab", 3, "cde", 20) != 40 { m = m + 2 }
  r := pick_lg("abcd", "q", 3)
  s := pick_ir("q", r, 1)
  if r.len != 4 or r[3] != 100 or s.len != 4 or s[0] != 97 { m = m + 4 }
  m
}
main := fn() -> u64 {
  a := drv_ir()
  b := drv_lg()
  if a != 0 { return 100 + a }
  if b != 0 { return 110 + b }
  42
}
## expect: run 42
