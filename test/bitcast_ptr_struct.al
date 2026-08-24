## e2e — a POINTER-TO-STRUCT type is preserved through `bitcast`. `p : ptr(mut Pt) = bitcast(ptr(mut
## Pt), addr)` must bind `p` as a pointer-to-struct (ek 7), so `p.x` / `p.x = v` resolve THROUGH the
## pointer (the down-growing pointee layout: field k at `-(k*8)(p)`) — not collapse every field onto
## `p`'s own slot as a bare scalar (the old behaviour, which wrote both fields to one word). `p` is
## offset into the mapped region so the down-growing fields stay in bounds. Returns 42 = 40 + 2.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  p : ptr(mut Pt) = unchecked bitcast(ptr(mut Pt), bitcast(usize, r) + 4096)
  p.x = 40
  p.y = 2
  p.x + p.y
}
