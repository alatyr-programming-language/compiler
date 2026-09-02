## Issue #345 / Types §§3.4, 4.4 — a preserved `bitcast(ptr([mut] T), …)` now reaches the lowerers as
## the VERBATIM target text instead of a pre-extracted pointee token, so the pointee is recovered by
## PARSING that text. The grammar permits blanks around those tokens: a fixed `ptr(` + `mut ` prefix
## test resolves only the canonical spelling and silently falls back to a word-sized `deref` on the
## others — the exact 7-byte over-read the sub-word deref mechanism exists to prevent.
##
## Byte 1 of the page is set to 1, so a widened load reads 298 rather than 42 and every spelling that
## regresses returns its own numbered code instead of trapping. All four codes are below 126.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  base := bitcast(usize, r)
  deref(unchecked bitcast(ptr(mut u64), base)) = 0
  deref(unchecked bitcast(ptr(mut u8), base)) = 42
  deref(unchecked bitcast(ptr(mut u8), base + 1)) = 1
  b0 := deref(unchecked bitcast(ptr(mut u8), base))
  if b0 != 42 { return 1 }
  b1 := deref(unchecked bitcast(ptr (mut u8), base))
  if b1 != 42 { return 2 }
  b2 := deref(unchecked bitcast(ptr( mut u8 ), base))
  if b2 != 42 { return 3 }
  b3 := deref(unchecked bitcast(ptr( u8 ), base))
  if b3 != 42 { return 4 }
  return 42
}
