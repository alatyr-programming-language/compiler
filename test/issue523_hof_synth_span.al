## e2e (issue #523) — the same class through the THIRD producer of a synthesized span: the capturing
## higher-order call. `parser::synth_hof_name` writes `__hoflam<fnpos>` into the AST arena and rebases
## its address the same way `synth_ident_span` does, and the driver deep-clones the generic body into
## that declaration and REWRITES the capturing call site to name it (FN-6 §6.2 — the mechanism
## `map_capture.al` exercises for a program that compiles). So the rewritten call's callee span is not
## a source offset either.
##
## This file is `map_capture.al` with the captured `k` left definitely-unassigned until AFTER the `map`
## call, so the Types §9.4 refusal lands on the rewritten call. Measured on the parent (71ea8df):
## rc=132, SIGILL, empty stderr — the same trap, reached without `defer` and without `@alloc`, which is
## what makes this a distinct producer rather than a second spelling of the same one.
##
## The clone keeps the ORIGINAL call site's own arguments in front of the appended captures, so the
## location falls back to the first of them and names the line of the call the programmer wrote.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  mut k : u64
  f := fn(x : u64) -> u64 { return x * k }
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut v := alloc::vec::new(u64, ptr(ar))
  mut i : u64 = 1
  while i <= 6 {
    alloc::vec::push(u64, v, i).expect("push")
    i = i + 1
  }
  s := alloc::vec::as_slice(u64, ptr(v))
  mut m := alloc::vec::map(u64, u64, ptr(ar), s, f)
  k = 2
  ms := alloc::vec::as_slice(u64, ptr(m))
  mut sum : u64 = 0
  mut j : usize = 0
  while j < ms.len {
    sum = sum + ms[j]
    j = j + 1
  }
  u64(sum)
}
