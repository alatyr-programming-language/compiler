## Issue #161 / Stdlib appendix §§5.2.1, 7: a failed OS-backed arena allocation
## returns the mapped IoError without constructing or exposing an invalid pointer.
## The zero-length failure must be InvalidInput, a positive impossible request must
## become an IoError, and a normal allocation remains releasable through the existing
## owning/free path. The expected result is 42.
main := fn() -> u64 {
  zero := std::os::arena(0)
  mut zero_ok : bool = false
  match zero {
    Result::Ok(a) => {
      std::os::free(a)
    }
    Result::Err(e) => {
      match e {
        std::io::IoError.InvalidInput => { zero_ok = true }
        _ => {}
      }
    }
  }

  huge := std::os::arena(18446744073709551615)
  mut mmap_error_ok : bool = false
  match huge {
    Result::Ok(a) => {
      std::os::free(a)
    }
    Result::Err(e) => { mmap_error_ok = true }
  }

  good := std::os::arena(4096)
  mut good_ok : bool = false
  match good {
    Result::Ok(a) => {
      mut ar := std::os::region(ptr(a))
      std::os::free(a)
      good_ok = true
    }
    Result::Err(e) => {}
  }

  if zero_ok {
    if mmap_error_ok {
      if good_ok { return 42 }
    }
  }
  return 1
}
