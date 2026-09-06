## e2e / issue #393 (residual) — the ARENA TYPE NAME, alone, must pull the ambient base prelude.
##
## `cli::ambient_paths` decides the prelude from a TEXTUAL scan of the user source. Its allocator-
## surface trigger used to be the bare name of the fallible-result type only, so a program that
## merely NAMES the arena — a parameter annotation and a struct literal, no constructor call, no
## allocation, no error enum — got no prelude at all and was rejected on its first line.
##
## Isolation is the point: this file contains none of the other names that now pull the same closure,
## so it fails on the parent unless the arena type name itself is a trigger. On the parent it is
## refused with `check: invalid`, located on the annotated signature below. The pointer is never
## dereferenced — only the arena's own fields are read — so the null base is inert.
##
## The four backends do not agree on this file, and the disagreement is older than this fixture: the
## integer-to-pointer `bitcast` that builds the inert base has no aarch64/riscv64 lowering, so those
## two emit a fail-loud `brk #0 // unsupported bitcast` and the corpus records `run/133` for them
## while x86_64 and wasm run 42. Reduced without any ambient name at all — the same literal over a
## locally declared 3-field struct — the parent compiler emits the same trap, so it is a backend gap,
## not a prelude one. A trap is a loud refusal, not a wrong value; the x86_64 and wasm rows carry the
## behavioural half.
##
## 42 means the check held; a miss owns code 100, never a sum or a product.
cap_of := fn(a : Arena) -> u64 { return u64(a.cap) }

main := fn() -> u64 {
  bp := unchecked bitcast(ptr(mut bits8), usize(0))
  a := Arena(base = bp, cap = 7, off = 0)
  if cap_of(a) != 7 { return 100 }
  return 42
}
