main := fn() -> u64 {
  value : u64 = 1
  value = 2
  return value
}
## expect: reject "immutable binding" "at line 3"
