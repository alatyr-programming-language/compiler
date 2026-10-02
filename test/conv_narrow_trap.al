## Types §4.2 (narrow row): a CHECKED narrowing `T(v)` traps when the value does not fit `T`. The u32
## value 810 does not fit u8, so `u8(x)` traps (x86_64 `ud2` → 132; the twins trap `narrow` through the
## shared IR's `fit`). Before #872, x86_64 silently answered 810 & 0xFF = 42. The masking form is
## `unchecked u8(v)` (`test/conv_narrow.al`). The parameter is u32, not #872's u16: a 16-bit parameter
## is still a sema gap on the twins, which then truncate through their legacy path (#878).
f := fn(x : u32) -> u8 { u8(x) }
main := fn() -> u64 { u64(f(810)) }
