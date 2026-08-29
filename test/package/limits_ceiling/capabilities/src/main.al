## Manifest ceilings cover both OS capability calls and allocation when the module has no file marker.
main := fn() -> u64 {
  std::io::print("")
  arena_result := std::os::arena(4096)
  mut out : u64 = 0
  match arena_result {
    Result::Ok(arena) => {
      _ := std::os::free(arena)
      out = 42
    }
    Result::Err(e) => { panic("limits_ceiling: OS arena allocation failed") }
  }
  return out
}
