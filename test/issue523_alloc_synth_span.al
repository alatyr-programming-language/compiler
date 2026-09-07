## e2e (issue #523) — the same class through the OTHER parse-time desugar. `@alloc(A) x := init`
## (Memory §2.4) becomes `x := alloc_into(A, init)`, and `parser::synth_ident_span` gives the
## `alloc_into` callee a span that is the AST-arena address of that written name rebased to
## `base_abs - src`. `(src + s)` recovers the name — which is what `sema` and `lower` read it for — but
## `s` is not a position in the source text.
##
## The desugared call is the value of the binding, so the Types §9.4 definite-assignment refusal on its
## initializer reports the CALL's span. Measured on the parent (71ea8df): rc=132, SIGILL, empty stderr.
##
## The location now falls back to the desugar's FIRST ARGUMENT, which is the allocator expression the
## programmer wrote inside `@alloc(...)` — so the line named is the line of the `@alloc` itself, which
## is the attribution Tooling §5 asks for. The two zero-argument `defer { }` chain markers
## (`__deferblk`/`__deferblkend`) and the explicit-`T` form's synthesized `isize` type argument have no
## argument to borrow and are accounted for by declining the location instead; no diagnostic reaches
## either today.
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
main := fn() -> u64 {
  neg1 : isize = 0 - 1
  r := unchecked sys_mmap(9, 0, 65536, 3, 34, bitcast(usize, neg1), 0)
  bp := unchecked bitcast(ptr(mut bits8), bitcast(usize, r))
  mut ar := arena_over(bp, 65536)
  mut u : isize
  @alloc(ar) x := u
  u = 1
  return 0
}
