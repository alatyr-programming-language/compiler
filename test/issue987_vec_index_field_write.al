## e2e / issue #987 — a field write through `v[i]` on a `Vec` is refused, not stored into the handle.
##
## Types §4.5 / Stdlib appendix §6: `v[i]` on a library aggregate is `v.at(i)`, which returns the
## element by value, and `v[i] = x` is `v.index_set(i, x)`, which writes a whole element. A field
## write through the index is neither, so the build must stop with a diagnostic that says why and
## names the read-modify-write form.
##
## Parent `7bb90a3a` (x86_64, omen): build rc 1 for an unrelated reason, the lowering's "tuple/array
## element field not resolvable" message, which names neither the form nor the fix.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
P := struct { a : u64, b : u64 }

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  mut v := vec::new(P, ptr(ar))
  p0 := v.push(P(a = 1, b = 2))
  v[0].a = 40
  e : P = vec::at(P, ptr(v), 0)
  f := v.free()
  e.a + e.b
}
