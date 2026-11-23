## e2e — #1865: a runtime index into a module-global word array is checked, `bound i, N` before any
## address is formed (Types §6.4, CG-13), so `g_at(4)` on a `[usize; 4]` must trap on every backend. The
## in-range call before it answers normally, so the trap is the index check and not the function.
## expect: trap
G : [usize; 4] = [39, 40, 41, 42]

g_at := fn(i : usize) -> usize { G[i] }

main := fn() -> u64 {
  if g_at(3) != 42 { return 1 }
  u64(g_at(4))
}
