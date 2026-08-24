## Types — a PARAMETERIZED `struct` spelling `Name := struct(T : type) { … }` is not Alatyr: the
## generic forms are `Name(T) := struct { … }` and the type-function
## `Name := fn(T : type) -> type { return struct { … } }`. The member parser used to consume the `(`
## as the body opener and walk off the token stream, killing the compiler with SIGILL (rc 132, core
## dumped) and NO diagnostic. It must be a located parse REJECT instead — an uncontrolled crash tells
## the user nothing about what to write.
Box := struct(T : type) { v : T }
main := fn() -> u64 {
  return 7
}
