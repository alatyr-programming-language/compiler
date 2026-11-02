## e2e / issue #988 — a UFCS call on a sub-word `Vec` is the same instance as its prefix form.
##
## `v.push(x)` with `v : Vec(u32)` omits the type argument, so the compiler infers it from the
## receiver. Below two words the inferred instance was tagged by the receiver's variable NAME
## (`push__v32`), and inside that instance `size(T)` was the 8-byte default: every UFCS `push` on a
## `Vec(u8/u16/u32)` stored with an 8-byte stride, and the elements read back at their true stride
## were the low and high halves of the wrong slots. Types §4.5: `v.push(x)` IS `push(v, x)`, which is
## `push(u32, v, x)` once `T` is inferred.
##
## Writes go through UFCS; reads spell their type argument, so a failure here is the write's. Each
## check owns a code from 100 up; 42 means all held.
##
## Parent `55fa477` with the #395 fix (x86_64, omen): built rc 0, ran to 100 where 42 was due — the
## `Vec(u32)` element 1 read 0 (the 8-byte stride put `2` in element 2).
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  mut v32 := vec::new(u32, ptr(ar))
  s0 := v32.push(40)
  s1 := v32.push(2)
  c0 : u32 = vec::at(u32, ptr(v32), 0)
  c1 : u32 = vec::at(u32, ptr(v32), 1)
  if u64(c1) != 2 { return 100 }
  if u64(c0) != 40 { return 101 }

  mut v8 := vec::new(u8, ptr(ar))
  p0 := v8.push(42)
  p1 := v8.push(149)
  p2 := v8.push(211)
  b1 : u8 = vec::at(u8, ptr(v8), 1)
  b2 : u8 = vec::at(u8, ptr(v8), 2)
  if u64(b1) != 149 { return 102 }
  if u64(b2) != 211 { return 103 }
  if v8.len != 3 { return 104 }

  mut v16 := vec::new(u16, ptr(ar))
  q0 := v16.push(4660)
  q1 := v16.push(22136)
  h1 : u16 = vec::at(u16, ptr(v16), 1)
  if u64(h1) != 22136 { return 105 }

  f8 := vec::free(u8, v8)
  f16 := vec::free(u16, v16)
  f32 := vec::free(u32, v32)
  42
}
## expect: run 42
