broken := fn() -> u64 {
  value := 1
}

main := fn() -> u64 {
  return 0
}
## expect: reject "at line 1"
