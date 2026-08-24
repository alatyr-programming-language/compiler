first := fn(s : [u8]) -> u64 { u64(s[0]) }

main := fn() -> u64 { first(bytes("*")) }
