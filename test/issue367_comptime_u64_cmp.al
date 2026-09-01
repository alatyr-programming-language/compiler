## Issue #367 / Types §3.2 and Comptime §§1.4–1.6: a typed comptime local used by an
## ordinary runtime comparison keeps its unsigned operation selection after materialization.
## The rows below deliberately use both operand orders for all six operators. The result is
## counted instead of bit-packed so every cross-backend process status stays below 126.
main := fn() -> u64 {
  comptime high : u64 = 9223372036854775808
  comptime max : u64 = 18446744073709551615
  comptime small : u64 = 5
  comptime signed_neg : i64 = 0 - 5
  comptime signed_zero : i64 = 0
  mut runtime_high : u64 = 9223372036854775808
  mut runtime_small : u64 = 5
  mut good : u64 = 0
  mut bad : u64 = 0

  ## comptime u64 ctslot rows: true cases, with high on each side of each ordering operator.
  if small < high { good = good + 1 }
  if high < max { good = good + 1 }
  if high > small { good = good + 1 }
  if max > high { good = good + 1 }
  if small <= high { good = good + 1 }
  if high <= max { good = good + 1 }
  if high >= small { good = good + 1 }
  if max >= high { good = good + 1 }
  if high == high { good = good + 1 }
  if high != max { good = good + 1 }
  if max != high { good = good + 1 }

  ## comptime u64 ctslot rows: false cases, again with both operand orders.
  if high < small { bad = bad + 1 }
  if max < high { bad = bad + 1 }
  if small > high { bad = bad + 1 }
  if high > max { bad = bad + 1 }
  if high <= small { bad = bad + 1 }
  if max <= high { bad = bad + 1 }
  if small >= high { bad = bad + 1 }
  if high >= max { bad = bad + 1 }
  if small == max { bad = bad + 1 }
  if max == small { bad = bad + 1 }
  if small != small { bad = bad + 1 }

  ## Ordinary runtime u64 controls: the ctslot lookup must not broaden the existing path.
  if runtime_small < runtime_high { good = good + 1 }
  if runtime_high > runtime_small { good = good + 1 }
  if runtime_small <= runtime_high { good = good + 1 }
  if runtime_high >= runtime_small { good = good + 1 }
  if runtime_small == runtime_high { bad = bad + 1 }
  if runtime_small != runtime_high { good = good + 1 }

  ## Signed comptime locals: signed i64 controls must remain on the signed condition family.
  if signed_neg < signed_zero { good = good + 1 }
  if signed_zero > signed_neg { good = good + 1 }
  if signed_neg <= signed_zero { good = good + 1 }
  if signed_zero >= signed_neg { good = good + 1 }
  if signed_neg == signed_zero { bad = bad + 1 }
  if signed_neg != signed_zero { good = good + 1 }

  ## 21 true rows and 13 false rows are expected. A compact failure code remains WASI-safe.
  if good == 21 { if bad == 0 { return 42 } }
  good * 4 + bad
}
