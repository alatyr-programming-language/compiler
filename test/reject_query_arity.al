## Capability queries require exactly one operand.
main := fn() -> u64 {
  compiles()
  42
}
## expect: reject
