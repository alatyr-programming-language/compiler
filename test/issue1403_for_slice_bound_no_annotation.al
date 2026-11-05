## e2e / issue #1403 — a `for` over a `Slice(T)` local bound WITHOUT an annotation steps by `T`'s width.
##
## `r := pass(t[0..4])` where `pass : Slice(u8) -> Slice(u8)` carries no `: Slice(u8)` at the binding
## site. The `for` arm read the element's width from that annotation (`slice_ann_elem_span`), so it
## answered nothing, `elem_w` kept its default word, and the loop stepped 8 bytes per element over a
## `u8` run — reading the seven bytes beside each element (the issue's `r := pass(…); for x in r` row,
## which answered 1 where 42 was due). Types §6.4 makes element access `base + i × stride` with the
## stride `T`'s size rounded up to its alignment; Control Flow §6 makes a slice iterable, yielding each
## element. The width now comes from the SLOT, which names the instantiated `Slice(u8)` (#1238's span
## substitution), so the loop and `r[i]` agree on one answer instead of two.
##
## A type PARAMETER (`pass : Slice(T) -> Slice(T)` at an unresolved `T`) names no width and keeps the
## word it had; a `str` element stays on the two-word pair path. Both are held here as controls.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `86078f37` (x86_64, omen): built rc 0, ran to **101** where 42 was due — `u8` stepped by the
## word. The `i8`, `Vec(u16)` and `Vec(u8)` rows of the same shape also answered wrong there.
##
## NOT covered here: a slice over a fixed array that x86_64 lays out one word per element
## (`[u16; N]`, `[u32; N]`, an inferred `[u8; N]`). That slice's pointer walks 8-byte-spaced elements,
## so a consumer stepping at Types §6.4's stride reads wrong. The defect is in the producer, not in
## this loop (#1514). Also still open on #1403: the fixed-array view rows (`v := t[1..4]; for x in v`,
## `for x in t[1..4]`).
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

pass8 := fn(s : Slice(u8)) -> Slice(u8) { s }
passi8 := fn(s : Slice(i8)) -> Slice(i8) { s }
pass16 := fn(s : Slice(u16)) -> Slice(u16) { s }
pass64 := fn(s : Slice(u64)) -> Slice(u64) { s }

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  ## u8: the issue's own repro. [1, 200, 3, 255] folded as n = n * 31 + i64(x).
  a8 : [u8; 4] = [1, 200, 3, 255]
  mut n8 : i64 = 0
  u8r := pass8(a8[0..4])
  for x in u8r { n8 = n8 * 31 + i64(x) }
  if n8 != 1 * 29791 + 200 * 961 + 3 * 31 + 255 { return 101 }
  if u64(u8r.len) != 4 { return 102 }

  ## i8: the same shape, SIGN-extended (Types §3.2): [1, -2, 3, -128].
  ai : [i8; 4] = [1, -2, 3, -128]
  mut ni : i64 = 0
  i8r := passi8(ai[0..4])
  for x in i8r { ni = ni * 31 + i64(x) }
  if ni != 1 * 29791 + (-2) * 961 + 3 * 31 + (-128) { return 103 }

  ## u16: stride 2, zero-extended. The run comes from a `Vec(u16)`, whose buffer is packed at
  ## Types §6.4's stride — NOT from a `[u16; N]` local, which x86_64 still lays out one word per
  ## element (#1514).
  mut v16 := alloc::vec::new(u16, ptr(ar))
  alloc::vec::push(u16, v16, 1000).expect("push")
  alloc::vec::push(u16, v16, 2000).expect("push")
  alloc::vec::push(u16, v16, 3000).expect("push")
  mut n16 : u64 = 0
  r16 := pass16(alloc::vec::as_slice(u16, ptr(v16)))
  for x in r16 { n16 = n16 * 10 + u64(x) }
  if n16 != 1000 * 100 + 2000 * 10 + 3000 { return 104 }

  ## u8 from a `Vec(u8)`: the issue's `vec::as_slice(u8, …)` row, through the same bound call.
  mut v8 := alloc::vec::new(u8, ptr(ar))
  alloc::vec::push(u8, v8, 7).expect("push")
  alloc::vec::push(u8, v8, 250).expect("push")
  mut nv8 : u64 = 0
  rv8 := pass8(alloc::vec::as_slice(u8, ptr(v8)))
  for x in rv8 { nv8 = nv8 * 1000 + u64(x) }
  if nv8 != 7250 { return 109 }

  ## CONTROL — a word element: this shape already answered right, and must not move.
  a64 : [u64; 3] = [7, 8, 9]
  mut n64 : u64 = 0
  r64 := pass64(a64[0..3])
  for x in r64 { n64 = n64 * 10 + x }
  if n64 != 789 { return 105 }

  ## CONTROL — the element read by index agrees with the loop's stride (one width, one answer).
  if u64(u8r[1]) != 200 { return 106 }
  if i8r[3] != -128 { return 107 }
  if u64(r16[2]) != 3000 { return 108 }
  42
}

## expect: run 42
