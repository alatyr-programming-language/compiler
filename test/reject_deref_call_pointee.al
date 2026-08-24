## P1-CLAYOUT S3(b), I11 loud boundary — `deref(f(...))` where `f` is declared `-> ptr(<its own type
## PARAMETER>)` and the call does NOT name a resolvable type argument at that parameter's position.
##
## The pointee is then unknowable at the use site: a scalar pointee is ONE machine word, a §7
## `str`/`[T]` view pointee is TWO (Types §7 — the view IS its pointer+length pair wherever it
## appears), and picking either width silently produces a wrong value for the other. Before this stage
## the lower took one word with no diagnostic and no trap.
##
## Here the type argument is a TUPLE type, which the type-argument reader cannot name (a bare `Var`
## and a generic instance `Box(u64)` both resolve; a tuple does not). Measured before this stage: the
## compiler accepted this program and ran it to exit 7 with NO diagnostic, having bound the pointee as
## one word. Now the build FAILS LOUD, with the offending source line written to stderr first. A trap
## is acceptable; a wrong value is not.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize

mk := fn(T : type, base : usize) -> ptr(mut T) { return unchecked bitcast(ptr(mut T), base) }

main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  base := unchecked bitcast(usize, bitcast(ptr(mut bits8), bitcast(usize, r)))
  x := deref(mk((u64, u64), base))
  return 7
}
