comptime if true { value := 1 }
main := fn() -> u64 { return 0 }
## expect: reject "standalone top-level"
