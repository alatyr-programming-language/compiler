## sema/limits: layout queries are compile-time/library-level abstraction, not the raw instruction
## surface allowed by `no_abstractions`.
@limits(no_abstractions)
main := fn() -> u64 {
  return u64.size()
}
