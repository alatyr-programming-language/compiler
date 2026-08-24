## sema/limits: `no_abstractions` admits only 1:1 instruction intrinsics and erased forms. A scalar
## conversion such as `u64(42)` is a builtin lowering decision, not a written instruction, so it must
## be rejected under the limit.
@limits(no_abstractions)
main := fn() -> u64 {
  return u64(42)
}
