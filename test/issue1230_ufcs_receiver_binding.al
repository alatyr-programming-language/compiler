## e2e / issue #1230 — a UFCS call reads its receiver's type from the binding that occurrence sees.
##
## `v.push(x)` on a `Vec(u32)` infers `T = u32` from the receiver (Types §4.5). #988 read the receiver's
## type from every binding of its NAME in the whole fn, and answered only when all of them agreed; a
## receiver copied from another local, or a name also bound in another block, was left unread, the
## instance was tagged by the name, and `size(T)` inside it was the 8-byte default: a `Vec(u32)` stored
## with an 8-byte stride. Scope is lexical and block-structured, and an inner declaration shadows only
## inside its block (Declarations §5–§6), so the binding the occurrence sees is the one that types it.
##
## The tail-expression and method-result receivers (106, 107) were right on the parent by the 8-byte
## coincidence; they guard against refusing a receiver whose type IS readable.
##
## Writes go through UFCS; reads spell their type argument, so a failure here is the write's. Each
## check owns a code from 100 up; 42 means all held.
##
## Parent `19b25a58` (main after #1218, x86_64, omen): exit 100.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

find := fn(k : u64) -> Option(u64) { if k == 1 { return Option(u64).Some(42) } ; Option(u64).None }

## the receiver occurrence is in the fn's TAIL expression, which sees the body's declarations
tail_unwrap := fn() -> u64 {
  o := find(1)
  o.unwrap()
}

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 65536, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 65536)

  ## a receiver copied from another local, twice over
  mut w := vec::new(u32, ptr(ar))
  mut c := w
  mut v := c
  s0 := v.push(40)
  s1 := v.push(2)
  c1 : u32 = vec::at(u32, ptr(v), 1)
  if u64(c1) != 2 { return 100 }

  ## the same name bound in an inner block with another type argument, before and after
  if true {
    mut d := vec::new(u64, ptr(ar))
    a0 := d.push(7)
    a1 := d.push(8)
    e1 : u64 = vec::at(u64, ptr(d), 1)
    if e1 != 8 { return 101 }
  }
  mut d := vec::new(u16, ptr(ar))
  t0 := d.push(4660)
  t1 := d.push(22136)
  h1 : u16 = vec::at(u16, ptr(d), 1)
  if u64(h1) != 22136 { return 102 }
  if true {
    mut d := vec::new(u8, ptr(ar))
    b0 := d.push(149)
    b1 := d.push(211)
    g1 : u8 = vec::at(u8, ptr(d), 1)
    if u64(g1) != 211 { return 103 }
  }
  u0 := d.push(13)
  h2 : u16 = vec::at(u16, ptr(d), 2)
  if u64(h2) != 13 { return 104 }
  if d.len != 3 { return 105 }

  if tail_unwrap() != 42 { return 106 }
  ## a receiver initialised by a method call with its type arguments omitted (`ok`'s `-> Option(T)`,
  ## `T` read from `r1`)
  r1 : Result(u64, u64) = Result.Ok(42)
  a := r1.ok()
  if a.unwrap() != 42 { return 107 }
  42
}
## expect: run 42
