## e2e — #1684, review of PR #1694 (B1): an `out` u8 parameter bound to an element of a `[u8; N]`
## array. Functions §2.3 binds it by a place argument the callee "reads and writes in place"; a `[u8; N]`
## is laid out one byte per element, and the x86_64 out-scalar callee stores a whole word through the
## address it receives. Passing the element's address therefore wrote eight bytes over a one-byte place.
## MEASURED (native x86_64, default / x86-legacy / x86-ir): the PR's first head d4461e92 answered **3**
## here — `b[2]` zeroed, a silent wrong value — and its parent 1b3b22e0 died with SIGSEGV (139). Until
## the callee writes its place at the declared width, x86_64 refuses this argument at its line; the
## program itself is valid and answers 42 once that lands (#1684's residual; the twins are #1692).
## spec: Functions §2.3, Memory §3.1/§3.3
set8 := fn(out x : u8) { x = 42 }

main := fn() -> u64 {
  mut b : [u8; 4] = [1, 2, 3, 4]
  set8(b[1])
  if b[0] != 1 { return 1 }
  if b[1] != 42 { return 2 }
  if b[2] != 3 { return 3 }
  if b[3] != 4 { return 4 }
  42
}
## expect: reject "a byte-packed array element is not supported as an out/in-out place argument on x86_64 yet"
