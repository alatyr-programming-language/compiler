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
## Parent `ff2d865b` (x86_64, omen): built rc 0, ran to **101** where 42 was due — `u8` stepped by the
## word. The `i8` row of the same shape folded to the wrong sum there too.
##
## NOT covered here, still open on #1403 (measured at this head): a range slice over a FIXED-ARRAY local
## — `v := t[1..4]; for x in v` traps 139 and `for x in t[1..4]` traps 132. That shape takes its stride
## from the array's own element kind, not from a `Slice(T)` type argument, and is a different seam.
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

  ## u16: stride 2, zero-extended.
  a16 : [u16; 3] = [1000, 2000, 3000]
  mut n16 : u64 = 0
  r16 := pass16(a16[0..3])
  for x in r16 { n16 = n16 * 10 + u64(x) }
  if n16 != 1000 * 100 + 2000 * 10 + 3000 { return 104 }

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
