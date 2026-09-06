## Issue #348 regression — the environment image ONE BYTE past the old fixed staging cap.
## `ALATYR_ENV_PROBE` is 16 bytes, so the process image is `16 + 1 ("=") + value + 1 (NUL)`: a
## 32751-byte value makes it 32769, one past the pre-#360 one-shot 32 KiB read. The cut then fell
## inside the only entry, no NUL terminator survived, the segment scan saw zero entries, and a
## PRESENT variable was answered `None`. This is the first size that was wrong, and it sits one
## byte from `issue348_env_at_image_cap`, which was the last size that was right.
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
          if bs.len != 32751 {
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
