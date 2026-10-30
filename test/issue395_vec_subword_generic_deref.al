## e2e / issue #395 — a `deref` inside a generic instance moves exactly `size(T)` bytes.
##
## `Vec(T)`'s element reads and writes go through `elem := unchecked bitcast(ptr(mut T), …)` and
## `deref(elem)`. Types §2 makes a `uN`/`iN` exactly its raw block, so at `T = u8` the read must
## return that one byte and the write must touch only it. On the parent the width resolver read the
## pointee's SOURCE spelling, `T`, which names no scalar, and so moved a whole word: `at` / `try_at`
## at `u8` returned the element with its seven neighbours above it, and `set` overwrote them.
##
## Every call spells its type argument (`vec::push(u8, v, x)`), so the UFCS instance tag (#988) is
## not involved. Neighbours are distinct and non-zero, so a word-wide read cannot pass as a benign
## zero. Each read is widened to `u64` before it is compared: a plain `b == 42` on the narrow value
## happened to pass on the parent, the widened word did not. Each check owns a code from 100 up;
## 42 means all of them held.
##
## Parent `55fa477` (x86_64, omen): built rc 0, ran to 100 where 42 was due. The `u8` read gave
## `0xD3952A` (13866282) for the stored `[42, 149, 211]`; at `u32` the read gave 42 + 2<<32.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## The `Option(u8)` payload widened to a word, or a value no byte can have when it is `None`.
opt_u8_word := fn(o : Option(u8)) -> u64 {
  match o {
    Option::Some(b) => {
      w : u64 = u64(b)
      w
    }
    Option::None => { 4096 }
  }
}

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  mut v8 := vec::new(u8, ptr(ar))
  p0 := vec::push(u8, v8, 42)
  p1 := vec::push(u8, v8, 149)
  p2 := vec::push(u8, v8, 211)
  a0 : u8 = vec::at(u8, ptr(v8), 0)
  w0 : u64 = u64(a0)
  if w0 != 42 { return 100 }
  if opt_u8_word(vec::try_at(u8, ptr(v8), 0)) != 42 { return 101 }
  if opt_u8_word(vec::get(u8, ptr(v8), 1)) != 149 { return 102 }
  uw : u64 = unchecked { opt_u8_word(vec::try_at(u8, ptr(v8), 2)) }
  if uw != 211 { return 103 }
  ## A write in the middle touches its own byte only.
  vec::set(u8, v8, 1, 7)
  if opt_u8_word(vec::try_at(u8, ptr(v8), 0)) != 42 { return 104 }
  if opt_u8_word(vec::try_at(u8, ptr(v8), 1)) != 7 { return 105 }
  if opt_u8_word(vec::try_at(u8, ptr(v8), 2)) != 211 { return 106 }

  mut v16 := vec::new(u16, ptr(ar))
  q0 := vec::push(u16, v16, 4660)
  q1 := vec::push(u16, v16, 22136)
  b1 : u16 = vec::at(u16, ptr(v16), 0)
  x1 : u64 = u64(b1)
  if x1 != 4660 { return 107 }

  mut v32 := vec::new(u32, ptr(ar))
  s0 := vec::push(u32, v32, 40)
  s1 := vec::push(u32, v32, 2)
  c0 : u32 = vec::at(u32, ptr(v32), 0)
  c1 : u32 = vec::at(u32, ptr(v32), 1)
  y : u64 = u64(c0) + u64(c1)
  if y != 42 { return 108 }

  ## A signed sub-word element sign-extends from its own byte, not from the word above it.
  mut vi := vec::new(i8, ptr(ar))
  t0 := vec::push(i8, vi, 0 - 5)
  t1 := vec::push(i8, vi, 100)
  d0 : i8 = vec::at(i8, ptr(vi), 0)
  e0 : i64 = i64(d0)
  if e0 != 0 - 5 { return 109 }

  ## The `u64` control, which was right before and must stay right.
  mut v64 := vec::new(u64, ptr(ar))
  u0 := vec::push(u64, v64, 40)
  u1 := vec::push(u64, v64, 2)
  if vec::at(u64, ptr(v64), 0) + vec::at(u64, ptr(v64), 1) != 42 { return 110 }

  f8 := vec::free(u8, v8)
  f16 := vec::free(u16, v16)
  f32 := vec::free(u32, v32)
  fi := vec::free(i8, vi)
  f64 := vec::free(u64, v64)
  42
}
