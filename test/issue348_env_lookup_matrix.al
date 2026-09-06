## Issue #348 residual — the environment LOOKUP matrix, measured twice by two rows that differ only
## in how much environment precedes the entries: once with nothing before them, and once with tens of
## kilobytes of generated filler in front, so every entry below starts past the old fixed 32 KiB
## staging read. The second row is what the pre-#360 one-shot read got wrong for a SMALL value: the
## entry was complete in the process image and still invisible, because the read stopped before it.
##
## The matrix itself is the part `issue348_env_long` does not cover: an `=` inside a value (only the
## FIRST `=` splits key from value), an EMPTY value (`Some("")`, never `None`), the LAST entry in the
## image, an absent name, and both prefix directions — a queried name that is a strict prefix of a
## present one, and a present name that is a strict prefix of the queried one. Neither may match.
##
## The runner supplies the whole environment under `env -i`, so nothing here depends on the
## environment of whoever runs the gate. Failure codes start at 100, each names one distinct wrong
## answer, none is computed, and all stay below 126. Every check is performed, but only the FIRST
## wrong answer is kept (`and code == 42`), so a run that loses several entries at once still reports
## the earliest one instead of whichever happened to be checked last.
eq_bytes := fn(s : str, want : str) -> bool {
  a := bytes(s)
  b := bytes(want)
  if a.len != b.len { return false }
  mut i : usize = 0
  while i < a.len {
    if a[i] != b[i] { return false }
    i += 1
  }
  return true
}

main := fn() -> u64 {
  arena_result := std::os::arena(4194304)
  match arena_result {
    Result::Ok(own) => {
      mut ar := std::os::region(ptr(own))
      mut code : u64 = 42

      probe := std::os::env(ptr(mut ar), "ALATYR_ENV_PROBE")
      match probe {
        Option::Some(s) => { if not eq_bytes(s, "probe-value") and code == 42 { code = 101 } }
        Option::None => { if code == 42 { code = 102 } }
      }

      inner_eq := std::os::env(ptr(mut ar), "ALATYR_ENV_EQ")
      match inner_eq {
        Option::Some(s) => { if not eq_bytes(s, "a=b=c") and code == 42 { code = 103 } }
        Option::None => { if code == 42 { code = 104 } }
      }

      empty := std::os::env(ptr(mut ar), "ALATYR_ENV_EMPTY")
      match empty {
        Option::Some(s) => { if not eq_bytes(s, "") and code == 42 { code = 105 } }
        Option::None => { if code == 42 { code = 106 } }
      }

      tail := std::os::env(ptr(mut ar), "ALATYR_ENV_TAIL")
      match tail {
        Option::Some(s) => { if not eq_bytes(s, "tail-value") and code == 42 { code = 107 } }
        Option::None => { if code == 42 { code = 108 } }
      }

      absent := std::os::env(ptr(mut ar), "ALATYR_ENV_ABSENT")
      match absent {
        Option::Some(s) => { if code == 42 { code = 109 } }
        Option::None => { }
      }

      shorter := std::os::env(ptr(mut ar), "ALATYR_ENV_PROB")
      match shorter {
        Option::Some(s) => { if code == 42 { code = 110 } }
        Option::None => { }
      }

      longer := std::os::env(ptr(mut ar), "ALATYR_ENV_PROBE_LONGER")
      match longer {
        Option::Some(s) => { if code == 42 { code = 111 } }
        Option::None => { }
      }

      std::os::free(own)
      return code
    }
    Result::Err(e) => { return 112 }
  }
}
