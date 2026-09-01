## Issue #346 regression: arguments crossing the initial process-input chunk stay ordered and exact.
main := fn() -> u64 {
  arena_result := std::os::arena(262144)
  match arena_result {
    Result::Ok(own) => {
      mut ar := std::os::region(ptr(own))
      av := std::os::args(ptr(mut ar))
      if av.len != 3 { std::os::free(own); return 1 }
      long_arg := bytes(av[1])
      tail := bytes(av[2])
      if long_arg.len != 70000 { std::os::free(own); return 2 }
      if tail.len != 4 { std::os::free(own); return 3 }
      if tail[0] != 116 or tail[1] != 97 or tail[2] != 105 or tail[3] != 108 {
        std::os::free(own)
        return 4
      }
      mut i : usize = 0
      mut ok : bool = true
      while i < long_arg.len {
        if long_arg[i] != 120 { ok = false }
        i += 1
      }
      std::os::free(own)
      if not ok { return 5 }
      return 42
    }
    Result::Err(e) => { return 6 }
  }
}
