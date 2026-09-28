## A GENERIC wide-SRET call whose result is DISCARDED (statement position, not the tail) must still be
## given a destination, on its own — with no earlier bound wide-SRET call to leave a usable hidden
## pointer in %rdi. This is the generic half of #711 that `rv64_sret_call_paths.al` only reaches masked:
## that fixture binds two wide-SRET results before its bare generic call, so a stale destination in %rdi
## can stand in for the missing one. Here the bare generic call is FIRST and binds nothing before it, so
## the only thing that can supply the destination is the fix itself.
##
## The callee returns its type PARAMETER (`-> T`), instantiated with a 9-word struct too wide for the
## register budget, so `sret_ret_call` (which reads a CONCRETE decl's declared return) is false and only
## `gen_ret_sret_span` (which resolves the return through the call's type argument) sees it. Before the
## fix, `call_needs_sret_dst` asked only the concrete half, so the discarded generic call reached
## `emit_call_args` with `cx.sret_call == -1` and the callee wrote 72 bytes through whatever %rdi held.
S9 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64 }

gmake := fn(T : type, n : u64) -> T {
  return S9(a = n, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9)
}

main := fn() -> u64 {
  gmake(S9, 1)
  d := gmake(S9, 1)
  return d.h + 34
}
