make := fn() -> [u8] { bytes("*") }

main := fn() -> u64 { u64(make()[0]) }
## expect: reject "at line 1"
