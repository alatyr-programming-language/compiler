## Issue #348 residual — the boundary the fix MOVED, and the proof that crossing it is LOUD.
##
## `std::os::env` no longer has a fixed 32 KiB image cap; what bounds it now is the caller's own
## allocator. This fixture hands it a deliberately tiny 4096-byte arena while the probe variable IS
## present in the environment, so the call cannot be satisfied and the only two possible outcomes are
## the loud one and the forbidden one.
##
## `Option(str)` has no error arm — Stdlib §7 defines the result as the variable's VALUE — so `None`
## can only mean "no such variable". Folding an exhausted allocator into `None` would assert that a
## present variable does not exist: a wrong value, not a diagnosis. The call must therefore abort.
##
## Reaching any `return` below already means it did not abort. Code 101 is the forbidden silent
## `None`; 102/103 mean it somehow answered. The row asserts the runtime diagnostic as well as the
## status, because a bare nonzero exit is also what code 101 produces — the needle lives on the row,
## never in this header.
main := fn() -> u64 {
  arena_result := std::os::arena(4096)
  match arena_result {
    Result::Ok(own) => {
      mut ar := std::os::region(ptr(own))
      r := std::os::env(ptr(mut ar), "ALATYR_ENV_PROBE")
      mut code : u64 = 102
      match r {
        Option::Some(s) => { code = 103 }
        Option::None => { code = 101 }
      }
      std::os::free(own)
      return code
    }
    Result::Err(e) => { return 104 }
  }
}
