## e2e / issue #987 — the index operator on a `Vec` calls the library's index functions.
##
## Types §4.5 / OP-3 and Stdlib appendix §6: `v[i]` is `v.at(i)`, `v[i] = x` is `v.index_set(i, x)`
## and `v[lo..hi]` is `v.index_range(lo, hi)` when `v` is a library aggregate. The compiler lowered
## all three as the BUILT-IN array index over the `Vec` handle's own words: the read gave the handle's
## first word, the write overwrote the handle and was lost, and the range viewed the handle. Arrays
## and slices keep the built-in index; the last checks hold that next to the new forms.
##
## Each check owns a code from 100 up; 42 means all held.
##
## Parent `7bb90a3a` (x86_64, omen): built rc 0, ran to 100 where 42 was due — `v[0]` did not read 40.
## Codes 111-117 (#1257): a `Vec(str)` range in every spelling, then a two-word struct range.
## Parent `19ba899e` (x86_64, omen) ran to 112 where 42 was due: `zs[1]` stepped one word and did not
## read "f". On that parent the struct checks alone ran to 116.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

## A two-word element for the #1257 range checks.
Pair := struct { a : u64, b : u64 }

## A `Vec` reached through a parameter, read and written by index.
bump := fn(in out v : vec::Vec(u64), i : usize) -> u64 {
  v[i] = v[i] + 1
  v[i]
}

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  mut v := vec::new(u64, ptr(ar))
  p0 := v.push(40)
  p1 := v.push(1)
  p2 := v.push(7)
  if v[0] != 40 { return 100 }
  if v[0] + v[1] != 41 { return 101 }
  v[2] = 2
  if vec::at(u64, ptr(v), 2) != 2 { return 102 }
  v[1] += 1
  if vec::at(u64, ptr(v), 1) != 2 { return 103 }
  s := v[0..2]
  if s.len != 2 { return 104 }
  if s[0] + s[1] != 42 { return 105 }
  if bump(v, 2) != 3 { return 106 }
  if vec::len(u64, ptr(v)) != 3 { return 107 }

  mut w := vec::new(u32, ptr(ar))
  q0 := w.push(40)
  q1 := w.push(9)
  w[1] = 2
  c : u32 = w[0] + w[1]
  if u64(c) != 42 { return 108 }

  mut a : [3]u64 = [5, 6, 7]
  a[1] = 30
  if a[0] + a[1] + a[2] != 42 { return 109 }
  t := a[1..3]
  if t[0] + t[1] != 37 { return 110 }

  ## #1257 — a `str` element: the view's element is a two-word pair, read at its own stride
  mut z := vec::new(str, ptr(ar))
  z0 := z.push("d")
  z1 := z.push("e")
  z2 := z.push("f")
  zs := z[1..3]
  if zs.len != 2 { return 111 }
  mut k : u64 = 0
  while k < 2 {
    if k == 1 and zs[k] != "f" { return 112 }
    k += 1
  }
  if zs[0] != "e" { return 113 }
  zu := z.index_range(0, 2)
  if zu[1] != "e" { return 114 }
  za : Slice(str) = z[2..3]
  if za[0] != "f" { return 115 }
  mut y := vec::new(Pair, ptr(ar))
  y0 := y.push(Pair(a = 1, b = 2))
  y1 := y.push(Pair(a = 3, b = 4))
  y2 := y.push(Pair(a = 5, b = 6))
  ys := y[1..3]
  e1 := ys[1]
  if e1.a != 5 or e1.b != 6 { return 116 }
  e0 := ys[0]
  if e0.a != 3 or e0.b != 4 { return 117 }

  f := v.free()
  g := w.free()
  h := z.free()
  hy := y.free()
  42
}
## expect: run 42
