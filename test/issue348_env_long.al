## Issue #348 regression: an environment value crossing `env`'s staging boundary stays COMPLETE and
## exact. `ALATYR_ENV_PROBE` is 70000 bytes — past the old fixed 32 KiB staging buffer and past the
## growable image's initial capacity — so the lookup must have read `/proc/self/environ` to EOF and
## grown, not stopped at its first chunk. The runner supplies the value under `env -i`, so this is
## the only variable in the measured environment. Failure codes start at 100 and each names one
## distinct wrong answer (no arithmetic that could alias success onto a failure).
main := fn() -> u64 {
  arena_result := std::os::arena(1048576)
  match arena_result {
    Result::Ok(own) => {
      mut ar := std::os::region(ptr(own))
      r := std::os::env(ptr(mut ar), "ALATYR_ENV_PROBE")
      mut code : u64 = 100
      match r {
        Option::Some(s) => {
          bs := bytes(s)
          if bs.len != 70000 {
            code = 101
          } else {
            if bs[bs.len - 1] != 90 {
              code = 102
            } else {
              mut bad : usize = 0
              mut i : usize = 0
              while i + 1 < bs.len {
                if bs[i] != 65 { bad += 1 }
                i += 1
              }
              if bad != 0 {
                code = 103
              } else {
                code = 42
              }
            }
          }
        }
        Option::None => { code = 104 }
      }
      std::os::free(own)
      return code
    }
    Result::Err(e) => { return 105 }
  }
}
