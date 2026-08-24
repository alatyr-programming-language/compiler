## e2e (§5 bare-prelude trigger). `print`/`println` are prelude names (Functions §7.1): a BARE
## `print("… {} …", args)` call is the specified spelling of `std::fmt::print` (the `{}`-template
## variadic), and bare `println(T, v)` renders one value + newline. The driver's module-injection
## scan now detects a bare `print`/`println(` call in USER source and injects `std/fmt.al` (which
## transitively pulls `std/io.al` + the base-prelude closure) — the qualified `std::fmt::print`
## was already reachable by the 3-segment scan, this adds the bare form. Dormant for the self-host
## build (`src/` uses no bare `print` call), so the TOOL-1 fixpoint is unaffected. Prints and returns 42.
main := fn() -> u64 {
  a : u64 = 40
  b : u64 = 2
  ## the third hole is an ARITHMETIC EXPRESSION (`a + b`) — an int-valued hole with no type span,
  ## rendered via the §7.1 default `print_one_int` (previously such a hole rendered nothing).
  print("{} + {} = {}\n", a, b, a + b)   ## bare variadic {}-template → std::fmt::print
  println(u64, 42)                        ## bare single-value renderer + newline
  42
}
