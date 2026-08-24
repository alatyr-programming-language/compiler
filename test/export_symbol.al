## MOD §6.3 (`@export`): a declaration carrying `@export("name")` emits the EXACT linker symbol
## `name` at its entry, regardless of the `pub` chain — for entry points / C interop. The fn is
## still callable internally under its mangled name (main → answer), and the exact symbol
## `alatyr_answer` is a global in the linked binary (the harness checks both: exit 42 + `nm`).
@export("alatyr_answer") answer := fn() -> u64 {
  return 42
}

main := fn() -> u64 {
  return answer()
}
