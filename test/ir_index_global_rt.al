## e2e — #1865: a runtime index into a module-global word array, `G[i]`, is built by the shared IR as
## `bound i, N` (Types §6.4, CG-13), then `addr @G` + `gep` at the 8-byte cell and a `load`. `G` is
## initialised by a repeat `[0; 4]` and written by `main`, `H` by literals; `top` reads `U`, a `[u64; 2]`,
## whose element compares unsigned (#707): `U[1]` is 2^63, above `U[0]`.
## 40 + 2 = 42.
## expect: run 42
mut G : [usize; 4] = [0; 4]
H : [i64; 4] = [-1, 2, 3, 4]
U : [u64; 2] = [1, 9223372036854775808]

g_at := fn(i : usize) -> usize { G[i] }
h_at := fn(i : usize) -> i64 { H[i] }
top := fn(i : usize, j : usize) -> bool { U[i] < U[j] }

main := fn() -> u64 {
  G[3] = 40
  if h_at(0) >= 0 { return 1 }
  if not top(0, 1) { return 2 }
  u64(g_at(3)) + u64(h_at(1))
}
