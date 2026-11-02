## e2e / issue #1238 — a `Slice(T)` view returned by the library generic carries `T`'s WIDTH.
##
## `alloc::vec::index_range(T, …)` and `alloc::vec::iter(T, …)` return a `Slice(T)` view over the
## vector's backing store. Types §6.4: element access is `base + i × stride`, the stride being `T`'s
## size rounded up to its alignment; Types §7: `[T]` is a pointer + length pair over a contiguous run
## of `T`. So an element of a `Slice(u16)` is TWO bytes at stride 2, and the x86_64 element read must
## be a 2-byte load (`movzwq`), not a word load that swallows the neighbouring elements' bytes.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `2d5ceb46` (x86_64, omen): built rc 0, ran to 101 where 42 was due — `t[0]` of a
## `Slice(u16)` read 8 bytes and kept element 2's low byte in its high bits (the issue's 55).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  ## u16: the issue's own repro — three pushed elements, a view over the last two.
  mut h := alloc::vec::new(u16, ptr(ar))
  q0 := h.push(30)
  q1 := h.push(5)
  q2 := h.push(7)
  t : Slice(u16) = alloc::vec::index_range(u16, ptr(h), 1, 3)
  if t.len != 2 { return 100 }
  x0 : u16 = t[0]
  x1 : u16 = t[1]
  if u64(x0) != 5 { return 101 }
  if u64(x1) != 7 { return 102 }

  ## u32: stride 4, zero-extended.
  mut v32 := alloc::vec::new(u32, ptr(ar))
  p0 := v32.push(4000000000)
  p1 := v32.push(1234567)
  p2 := v32.push(99)
  s32 : Slice(u32) = alloc::vec::index_range(u32, ptr(v32), 1, 3)
  if s32.len != 2 { return 103 }
  y0 : u32 = s32[0]
  y1 : u32 = s32[1]
  if u64(y0) != 1234567 { return 104 }
  if u64(y1) != 99 { return 105 }

  ## i16: stride 2, sign-extended load — a POSITIVE element still reads its own two bytes. (A
  ## NEGATIVE element is NOT covered here: `push` of a negative into a sub-word `Vec` traps today,
  ## which is a separate defect, filed with this measurement.)
  mut v16 := alloc::vec::new(i16, ptr(ar))
  n0 := v16.push(1)
  n1 := v16.push(300)
  n2 := v16.push(7)
  s16 : Slice(i16) = alloc::vec::index_range(i16, ptr(v16), 1, 3)
  z0 : i16 = s16[0]
  if i64(z0) != 300 { return 106 }

  ## bool: one byte per element (Types §7, `bool` is a single byte), not a word.
  mut vb := alloc::vec::new(bool, ptr(ar))
  b0 := vb.push(true)
  b1 := vb.push(false)
  b2 := vb.push(true)
  sb : Slice(bool) = alloc::vec::index_range(bool, ptr(vb), 1, 3)
  if sb.len != 2 { return 107 }
  c0 : bool = sb[0]
  c1 : bool = sb[1]
  if c0 != false { return 108 }
  if c1 != true { return 109 }

  ## u8: the byte tier already worked; held here so the fix cannot move it.
  mut v8 := alloc::vec::new(u8, ptr(ar))
  e0 := v8.push(10)
  e1 := v8.push(20)
  e2 := v8.push(30)
  s8 : Slice(u8) = alloc::vec::index_range(u8, ptr(v8), 1, 3)
  if u64(s8[0]) != 20 { return 110 }
  if u64(s8[1]) != 30 { return 111 }

  ## i8: one byte per element, SIGN-extended (Types §3.2). Positive here for the reason above.
  mut vi := alloc::vec::new(i8, ptr(ar))
  g0 := vi.push(1)
  g1 := vi.push(7)
  g2 := vi.push(3)
  si : Slice(i8) = alloc::vec::index_range(i8, ptr(vi), 1, 3)
  if i64(si[0]) != 7 { return 113 }

  ## A write through the narrow view touches that element's TWO bytes and no neighbour.
  t[0] = 11
  if u64(alloc::vec::at(u16, ptr(h), 1)) != 11 { return 114 }
  if u64(alloc::vec::at(u16, ptr(h), 2)) != 7 { return 115 }

  ## `iter` is the same view (`as_slice`), so a loop over the bound view reads the same elements:
  ## 30 + 11 + 7. (The iterable written as a DIRECT call in the loop header is still wrong and is
  ## #1421, which this fixture's measurement filed.)
  mut sum : u64 = 0
  it : Slice(u16) = alloc::vec::iter(u16, ptr(h))
  unchecked {
    for x in it {
      sum = sum + u64(x)
    }
  }
  if sum != 48 { return 112 }
  42
}

## expect: run 42
