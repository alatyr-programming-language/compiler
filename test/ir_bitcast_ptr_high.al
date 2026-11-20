## e2e — IR-35 (#980): an address FABRICATED with bits above 2^32 must not read another location on
## wasm. Memory §1.4: an address fabricated under `unchecked` "denotes whatever location its bits name",
## and an access through one that names no valid place has hardware-defined behavior (I11). `get`
## fabricates `s`'s own address plus 2^32 and `rd` reads through it.
##
## Natively that address is far from any mapping (a stack address plus 4 GiB), so the access faults:
## SIGSEGV, status 139, on x86_64, aarch64 and riscv64. wasm's linear memory is indexed by an i32: an
## address at or above 2^32 names none of it, so the trap is wasm's answer too (`unreachable`, 134).
## What it must NOT do is drop the top 32 bits and read `s.w` back. The wasm selector did exactly that
## when the `bits` here was first selected from the shared IR (review of PR #1787: run to 42).
S := struct { v : u64, w : u64 }
rd := fn(p : ptr(S)) -> u64 { deref(p).w }
addr := fn(p : ptr(S)) -> usize { unchecked bitcast(usize, p) }
get := fn(a : usize) -> u64 {
  q := unchecked bitcast(ptr(S), a + 4294967296)
  rd(q)
}
main := fn() -> u64 {
  s := S(v = 1, w = 42)
  get(addr(ptr(s)))
}
## expect(x86_64): run 139
## expect(aarch64): run 139
## expect(riscv64): run 139
## expect(wasm): trap
