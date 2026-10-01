## Issue #806 / Control Flow §5.4 — a range arm over an UNSIGNED 64-bit scrutinee compares unsigned.
## `a..=b` matches `a ≤ x ≤ b` in the scrutinee's type. x86_64 compared the bounds as signed `i64`,
## so a bound at or above 2^63 read as negative: `10..=18446744073709551615` never matched `u64::MAX`,
## `0..9223372036854775808` did not match 7, and the high `u64` value landed in the wrong arm. The
## parent built this program and ran it to 17. A signed `i64` range stays signed.
wide := fn(n : u64) -> u64 {
  r := match n { 0..=9 => { 1 }; 10..=18446744073709551615 => { 4 } }
  return r
}
top := fn(n : u64) -> u64 {
  r := match n { 0..9223372036854775808 => { 1 }; 9223372036854775808..=18446744073709551615 => { 10 } }
  return r
}
word := fn(n : usize) -> u64 {
  match n { 0..=99 => { return 2 }; 100..=18446744073709551615 => { return 20 } }
  return 0
}
signed := fn(n : i64) -> u64 {
  r := match n { -9223372036854775808..=-1 => { 6 }; 0..=9223372036854775807 => { 0 } }
  return r
}
main := fn() -> u64 {
  mut total : u64 = wide(3) + wide(18446744073709551615)
  total += top(7) + top(9223372036854775813)
  total += word(18446744073709551000)
  total += signed(0 - 5)
  return total
}
