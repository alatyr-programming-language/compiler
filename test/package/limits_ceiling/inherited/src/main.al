## Manifest ceiling must apply to a module that has no file-level @limits marker.
main := fn() -> u64 {
  return unchecked (40 + 2)
}
