## Types §4.4 + I11 (§4.2 numeric row): a CHECKED signedness-changing conversion `T(v)` traps when the
## value does not fit `T`. The i64 value -1 is not a u64, so `u64(x)` traps (x86_64 `ud2` → 132; the
## twins trap `narrow` through the shared IR's `fit`). Before #881, x86_64 silently answered
## 18446744073709551615 (the bit reinterpretation). The reinterpreting form is `unchecked u64(x)`.
f := fn(x : i64) -> u64 { u64(x) }
main := fn() -> u64 { f(0 - 1) }
