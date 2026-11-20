## e2e — IR-35 (#980): a fabricated address whose top 32 bits are ZERO, read at a field offset that
## carries it past 2^32, must not read another location on wasm. Memory §1.4 and §4.5: an address
## fabricated under `unchecked` "denotes whatever location its bits name", pointer arithmetic included,
## and an access through one that names no valid place has hardware-defined behavior (I11).
##
## `get` fabricates 2^32 - 8, which passes any check of the pointer's own top bits, and `rd` reads its
## second field, eight bytes on: the address 2^32. Natively nothing is mapped there (a static binary
## sits far below it), so the access faults, SIGSEGV, status 139, on x86_64, aarch64 and riscv64. In
## wasm's i32-indexed linear memory 2^32 names no location, so the trap (`unreachable`, 134) is wasm's
## answer too. Wrapping the address to 32 bits would read linear memory at 0 instead, and run to
## whatever word lies there.
S := struct { v : u64, w : u64 }
rd := fn(p : ptr(S)) -> u64 { deref(p).w }
get := fn(a : usize) -> u64 {
  q := unchecked bitcast(ptr(S), a)
  rd(q)
}
main := fn() -> u64 { get(4294967288) }
## expect(x86_64): run 139
## expect(aarch64): run 139
## expect(riscv64): run 139
## expect(wasm): trap
