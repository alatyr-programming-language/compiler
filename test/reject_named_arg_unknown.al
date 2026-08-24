## FN §5.1 fail-loud: a named argument whose name matches NO parameter is rejected (would otherwise be a
## silent 0-struct miscompile — the parser mis-parses it as a struct literal of the fn name). `c` is not
## a parameter of `diff`.
diff := fn(a : u64, b : u64) -> u64 { return a - b }
main := fn() -> u64 { return diff(a = 50, c = 8) }
