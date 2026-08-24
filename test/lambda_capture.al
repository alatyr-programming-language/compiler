## FN-6 CAPTURE (static closure, first slice) — a lambda that references an enclosing LOCAL `c`
## captures it. The driver's lift pass appends each captured var as a trailing PARAM to the lifted fn
## AND injects it as a trailing ARG at every direct call `f(n)` → `f(n, c)`; lower then sees a plain
## multi-arg indirect call. `c := 2; f(40)` = 42. (Node building for the appended params/args runs via
## the parser module's `pnode`/`newnode`/`gnode`/`set_*_next` — the identical stores mis-lower in the
## driver module, a cross-module codegen quirk found with gdb: the store wrote a stack pointer, not the
## struct.) An ESCAPING capturing lambda (passed as a value) is rejected fail-loud — see the reject test.
main := fn() -> u64 {
  c := 2
  f := fn(n : u64) -> u64 { return n + c }
  return f(40)
}
