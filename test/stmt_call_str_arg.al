## A call in STATEMENT position (its result discarded) whose argument is a `str` LOCAL — the most
## ordinary line a program writes. It silently emitted NOTHING: `std::io::print` was resolved by
## TAIL NAME against the comptime-variadic `std::fmt::print`, so the statement was routed into the
## `{}`-template desugar, which returns without emitting anything when arg 0 is not a string
## literal. The call and its side effect vanished with no diagnostic (I11).
##
## Covered: a `str` LOCAL, a `str` PARAMETER, a `while` body, an `if` branch, a call whose result
## is DISCARDED against the value-position form (`k := io::print(...)`) that already worked and must
## keep working. The countable helper is deliberately named `print` — only a callee whose tail name
## collides with the variadic one triggers the defect, so this is the one way a DISCARDED call's
## having-run can be observed from inside the program: the exit code carries the count (42), so the
## gate does not rest on stdout alone, and `run_x86_out` additionally checks the exact bytes against
## `test/stmt_call_str_arg.out`.
io := std::io
mut CNT : u64 = 0
print := fn(t : str) -> u64 {
  io::print(t)            ## a `str` PARAMETER, statement position
  CNT = CNT + 1
  return 1
}
main := fn() -> u64 {
  s : str = "L\n"
  io::print(s)            ## a `str` LOCAL, qualified callee, statement position
  print(s)                ## a user fn taking `str`, statement position
  mut i : u64 = 0
  while i < 2 {
    print(s)              ## inside a `while` body
    i = i + 1
  }
  if i == 2 {
    print(s)              ## inside an `if` branch
  }
  k := io::print("V\n")   ## value position: the path that already worked
  return CNT + 38
}
