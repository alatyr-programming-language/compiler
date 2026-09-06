## Issue #348 control — the environment image EXACTLY at the old fixed staging cap.
## `ALATYR_ENV_PROBE` is 16 bytes, so the process image is `16 + 1 ("=") + value + 1 (NUL)`: a
## 32750-byte value makes it exactly 32768, the last byte being the terminating NUL. This is the
## LAST size the pre-#360 one-shot 32 KiB read got right, and it is here so the pair of rows
## measures the boundary from BOTH sides rather than only "a big value works".
## The runner supplies the value under `env -i`, so this is the only variable in the measured
## environment. Failure codes start at 100, each names one distinct wrong answer, and none is
## computed — no arithmetic that could alias a wrong answer onto success.
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
          if bs.len != 32750 {
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
