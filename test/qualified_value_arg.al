## e2e — an ordinary generic call must keep a qualified VALUE/type path as one argument.
## `ser::SerError` is not a generic-enum constructor tail: the call parser must consume the
## qualified path and stop at the call's closing `)`, leaving the following declaration intact.
ser := std::serialize

pick := fn(T : type, E : type) -> u64 { return 42 }

main := fn() -> u64 {
  return pick(usize, ser::SerError)
}
