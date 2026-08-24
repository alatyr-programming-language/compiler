max := fn(a : u64, b : u64) -> u64 { return if a > b { a } else { b } }
main := fn() -> u64 { return max(42, 17) }
