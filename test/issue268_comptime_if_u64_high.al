## Issue #268 / Types §3.2 and Comptime §9.1: a closed comptime-if comparison over typed u64
## bindings uses unsigned ordering at the high-bit and MAX boundaries. Each selected branch adds to
## one of two counters, so a signed fold returns a distinct non-success code instead of disappearing.
main := fn() -> u64 {
  comptime high : u64 = 9223372036854775808
  comptime max : u64 = 18446744073709551615
  comptime one : u64 = 1
  comptime signed_neg : i64 = 0 - 5
  comptime signed_zero : i64 = 0
  mut good : u64 = 0
  mut bad : u64 = 0

  comptime if high < one { bad = bad + 1 } else { good = good + 1 }
  comptime if high <= one { bad = bad + 1 } else { good = good + 1 }
  comptime if high > one { good = good + 1 } else { bad = bad + 1 }
  comptime if high >= one { good = good + 1 } else { bad = bad + 1 }
  comptime if high == one { bad = bad + 1 } else { good = good + 1 }
  comptime if high != one { good = good + 1 } else { bad = bad + 1 }

  comptime if one < high { good = good + 1 } else { bad = bad + 1 }
  comptime if one <= high { good = good + 1 } else { bad = bad + 1 }
  comptime if one > high { bad = bad + 1 } else { good = good + 1 }
  comptime if one >= high { bad = bad + 1 } else { good = good + 1 }
  comptime if one == high { bad = bad + 1 } else { good = good + 1 }
  comptime if one != high { good = good + 1 } else { bad = bad + 1 }

  comptime if max < high { bad = bad + 1 } else { good = good + 1 }
  comptime if max <= high { bad = bad + 1 } else { good = good + 1 }
  comptime if max > high { good = good + 1 } else { bad = bad + 1 }
  comptime if max >= high { good = good + 1 } else { bad = bad + 1 }
  comptime if max == high { bad = bad + 1 } else { good = good + 1 }
  comptime if max != high { good = good + 1 } else { bad = bad + 1 }

  comptime if high < max { good = good + 1 } else { bad = bad + 1 }
  comptime if high <= max { good = good + 1 } else { bad = bad + 1 }
  comptime if high > max { bad = bad + 1 } else { good = good + 1 }
  comptime if high >= max { bad = bad + 1 } else { good = good + 1 }
  comptime if high == max { bad = bad + 1 } else { good = good + 1 }
  comptime if high != max { good = good + 1 } else { bad = bad + 1 }

  ## Signed controls must keep signed ordering even beside the unsigned matrix.
  comptime if signed_neg < signed_zero { good = good + 1 } else { bad = bad + 1 }
  comptime if signed_zero > signed_neg { good = good + 1 } else { bad = bad + 1 }
  comptime if signed_neg == signed_zero { bad = bad + 1 } else { good = good + 1 }

  ## Twenty-seven correct selections are required; any wrong branch is observable below 126.
  if good == 27 and bad == 0 { return 42 }
  good * 4 + bad
}
