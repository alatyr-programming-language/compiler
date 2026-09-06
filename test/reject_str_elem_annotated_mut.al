## Issue #429 — the annotated half of the same hole. `mut s : str = "abc"` records the declared
## type, so the binding's own permission class is `mut` and the established #298 fence stands
## down; the element permission still belongs to the view's pointer and still refuses.
##
## The two spellings reached the fault by DIFFERENT routes on the parent, which is why both are
## here: without the annotation the checker recorded no type at all for the binding (the packed
## `Result(Ty, …)` carrier drops a string literal's tag), and with it the recorded type carried
## the `mut` bit that the permission query reads as "writable". Measured on the parent
## (d18fb3f): built clean, x86_64 exit 139 (SIGSEGV).
main := fn() -> u64 {
  mut s : str = "abc"
  s[0] = 65
  7
}
