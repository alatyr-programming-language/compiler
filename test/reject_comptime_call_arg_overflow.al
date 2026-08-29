## Failure-first parent f98c62f1330ef3e86367eca024e441fa6fc42570: check rc 0; build rc 0 produced an
## ELF artifact; running it under ulimit -c 0 returned rc 132 (SIGILL).
take := fn(v : u64) -> u64 {
  return v
}

main := fn() -> u64 {
  return take(18446744073709551615 + 1)
}
