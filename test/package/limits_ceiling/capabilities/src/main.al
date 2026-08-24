## Manifest ceilings cover both OS capability calls and allocation when the module has no file marker.
main := fn() -> u64 {
  std::io::print("")
  arena := std::os::arena(4096)
  _ := std::os::free(arena)
  42
}
