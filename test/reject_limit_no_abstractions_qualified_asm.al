## sema/limits: the raw assembly allow-list is the direct intrinsic spelling (`movq(...)`). The
## qualified namespace spelling is deliberately outside the first-slice 1:1 surface.
@limits(no_abstractions)
main := fn() -> u64 {
  x86_64::movq(rax, 60)
  return 0
}
