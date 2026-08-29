## Parent f98c62f measurement: check and build both returned 0, and build produced an artifact.
main := fn() -> u64 {
  hidden := Target(arch = Arch.x86_64)
  return 42
}
