## Issue #346 control: a non-zero argument below the initial process-input chunk remains complete.
main := fn() -> u64 {
  arena_result := std::os::arena(262144)
  match arena_result {
    Result::Ok(own) => {
      mut ar := std::os::region(ptr(own))
      av := std::os::args(ptr(mut ar))
      if av.len != 2 { std::os::free(own); return 1 }
      arg := bytes(av[1])
      if arg.len != 65000 { std::os::free(own); return 2 }
      mut i : usize = 0
      mut ok : bool = true
      while i < arg.len {
        if arg[i] != 99 { ok = false }
        i += 1
      }
      std::os::free(own)
      if not ok { return 3 }
      return 42
    }
    Result::Err(e) => { return 4 }
  }
}
