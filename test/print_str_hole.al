## e2e — `{}`-template `print` holes of DIFFERENT kinds in one call: a `str` VAR, a bare INT LITERAL,
## and a `str` LITERAL. A str hole (var or literal) writes its bytes via `io::print`; an int literal
## via `print_one_int`. Prints "hi Alice, you are 30" then "tag: X" (verified manually) and returns
## 42 — checks mixed-kind hole routing compiles, links, and runs.
main := fn() -> u64 {
  name : str = "Alice"
  std::fmt::print("hi {}, you are {}\n", name, 30)
  std::fmt::print("tag: {}\n", "X")
  42
}
