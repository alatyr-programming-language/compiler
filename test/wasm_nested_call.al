inc := fn(x : u64) -> u64 { return x + 1 }
dbl := fn(x : u64) -> u64 { return x * 2 }
main := fn() -> u64 { return dbl(inc(20)) }
