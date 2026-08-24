## e2e — CT-12, the `unchecked` half (the shift twin of `reject_comptime_unchecked_div_zero`): an
## over-width shift stays a diagnostic inside an `unchecked` scope. Dropping the width guard used to
## leave the x86 `shlq %cl` mask to decide the answer — `shl(1, 64)` silently evaluated to `1`, a
## machine-specific value the spec requires to be reproducible across machines (§2.2).
## Located at the shift (line 6).
K : u64 = unchecked shl(1, 64)

main := fn() -> i64 {
  return i64(K)
}
