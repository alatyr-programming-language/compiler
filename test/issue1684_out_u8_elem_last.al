## e2e — #1684, review of PR #1694 (B1): the same `out` u8 element argument at the LAST element, where
## the callee's whole-word store runs past the end of the `[u8; 4]` into the next frame slot. MEASURED
## (native x86_64, default / x86-legacy / x86-ir): the PR's first head d4461e92 answered **5** here —
## the unrelated local `k` overwritten — and its parent 1b3b22e0 died with SIGSEGV (139). x86_64 now
## refuses the argument at its line until the callee writes its place at the declared width; the
## program is valid and answers 42 once that lands (#1684's residual; the twins are #1692).
## spec: Functions §2.3, Memory §3.1/§3.3
set8 := fn(out x : u8) { x = 42 }

main := fn() -> u64 {
  mut k : u64 = 7
  mut b : [u8; 4] = [1, 2, 3, 4]
  mut j : u64 = 9
  set8(b[3])
  if b[3] != 42 { return 2 }
  if k != 7 { return 5 }
  if j != 9 { return 6 }
  if b[2] != 3 { return 3 }
  42
}
## expect: reject "a byte-packed array element is not supported as an out/in-out place argument on x86_64 yet"
