## e2e / issue #1230 — a UFCS call whose receiver's type the compiler does not read is refused.
##
## `mut v := h.items` copies a `Vec(u32)` out of a struct field. The receiver lookup reads a binding's
## annotation, a generic or method call's declared result, or another local it copies; it does not
## read a field's type. The parent tagged the instance by the receiver's name, so `size(T)` inside
## `push` was the 8-byte default and the `Vec(u32)` was stored with an 8-byte stride: exit 100, a
## silent wrong value. Types §4.5 infers `T` from the receiver's type. Where that type is not read the
## call must be refused at its line (a located reject, never a guess), and the explicit form
## `vec::push(u32, ptr(v), x)` stays expressible.
##
## Expected: the build is rejected at the `v.push` line, leaving no artifact.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
H := struct { items : vec::Vec(u32) }

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)
  h := H(items = vec::new(u32, ptr(ar)))
  mut v := h.items
  s0 := v.push(40)
  s1 := v.push(2)
  c1 : u32 = vec::at(u32, ptr(v), 1)
  if u64(c1) != 2 { return 100 }
  42
}
## expect: reject "cannot be inferred from its receiver"
