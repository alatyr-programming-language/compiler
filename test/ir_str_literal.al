## e2e — #1576: a `str` literal is built by the shared IR as the two-word view of its bytes (Types §7:
## a `str` is a view of UTF-8 bytes `[u8]`, pointer + length), its bytes addressed read-only
## (docs/ir.md §4: `addr @rodata` plus the length). Read by `.len` and by `s[i]` (Stdlib appendix
## §3.6: the slice read plus a code-point-boundary check, which `unchecked` drops whole), copied whole
## (`u := t`), with the source escapes decoded once (`\x41`, `\n`, `\\`) and a two-byte code point.
## Measured on the parent (`774ba852`): x86_64 answered 42; the legacy aarch64 and riscv64 emitters
## cannot lower a `str` literal (`brk #0 // unsupported expr StrLit`) and exited 133, and legacy wasm
## exited 134.
main := fn() -> i32 {
  s := "a*\x41\n\\"
  if s.len != 5 { return 1 }
  if s[0] != 97 or s[2] != 65 or s[3] != 10 or s[4] != 92 { return 2 }
  t : str = "é!"
  u := t
  if u.len != 3 { return 3 }
  if u[0] != 195 or u[2] != 33 { return 4 }
  ## Byte 1 continues `é`: the checked read would trap; `unchecked` drops the whole guard.
  if unchecked u[1] != 169 { return 5 }
  i32(s[1])
}
## expect: run 42
