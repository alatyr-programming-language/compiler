## Types §4.4 + I11 (§4.2 numeric row): the same-width signedness change `i32(x : u32)` is checked too.
## 3000000000 is a u32 but not an i32, so `i32(x)` traps (x86_64 `ud2` → 132, on the conversion's text
## path; `conv_signed_trap` covers the register-allocated `u64(x)`; the twins trap `narrow` through the
## shared IR's `fit`). Before #881, x86_64 silently answered the reinterpreted -1294967296.
f := fn(x : u32) -> i32 { i32(x) }
main := fn() -> u64 { u64(unchecked u32(f(3000000000))) }
