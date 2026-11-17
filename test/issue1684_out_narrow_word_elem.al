## e2e — #1684, review of PR #1694 (B1): the control for the byte-element refusal. Elements of
## `[u16; N]`, `[u32; N]`, `[i32; N]` and `[bool; N]` arrays are each laid out in an 8-byte cell on
## x86_64, so the out-scalar callee's whole-word store fits the element exactly and the place argument
## is passed, not refused: each callee's write lands in its element and no neighbour moves. The refusal
## must stay narrowed to one-byte elements; a refusal that fired here would be the over-reach.
## MEASURED (native x86_64): 139 (SIGSEGV) at 1b3b22e0, 42 at d4461e92 and at this fix.
## x86_64-scoped (`run_x86`) like the other #1684 rows; the twins are #1692.
## spec: Functions §2.3, Memory §3.1/§3.3
## expect(x86_64): run 42
s16 := fn(out x : u16) { x = 42 }
s32 := fn(out x : u32) { x = 42 }
si32 := fn(in out x : i32) { x = x + 40 }
sb := fn(out x : bool) { x = true }

main := fn() -> u64 {
  mut h : [u16; 4] = [1, 2, 3, 4]
  mut w : [u32; 4] = [1, 2, 3, 4]
  mut s : [i32; 3] = [2, 2, 3]
  mut f : [bool; 4] = [false, false, false, false]
  s16(h[1])
  s32(w[2])
  si32(s[0])
  sb(f[3])
  if h[1] != 42 or h[0] != 1 or h[2] != 3 { return 1 }
  if w[2] != 42 or w[1] != 2 or w[3] != 4 { return 2 }
  if s[0] != 42 or s[1] != 2 { return 3 }
  if not f[3] or f[2] { return 4 }
  42
}
