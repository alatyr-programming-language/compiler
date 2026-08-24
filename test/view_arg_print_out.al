## e2e stdout golden (I11 — the three silent `str`-argument defects, checked on the ORIGINAL
## observable). Each line is one of the reported repros, in STATEMENT position, where the failure was
## invisible: `io::print(p.name)` printed nothing, `io::print(sub(s, 0, 5))` SIGSEGV'd (exit 139),
## and `println(s)` for a `str` local printed `0` through the generic `display` path. The exact-stdout
## check is what an exit code cannot give: a wrong LENGTH or a wrong POINTER changes the bytes.
## The first and last lines are the POSITIVE CONTROLS — a plain `str` local and a `str` LITERAL, the
## paths that always worked. Prints six lines and returns 42.
P := struct { name : str, n : u64 }

main := fn() -> u64 {
  p := P(name = "Alice", n = 7)
  s : str = "AliceBob"
  xs : [str; 2] = ["Carolyn", "Bo"]
  println(s)                     ## the generic renderer with T INFERRED = str
  std::io::print(p.name)         ## a view FIELD as an argument
  std::io::print("\n")
  std::io::print(sub(s, 5, 3))   ## a `sub(…)` view as an argument
  std::io::print("\n")
  std::io::print(s[0..5])        ## a range sub-view as an argument
  std::io::print("\n")
  std::io::print(xs[0])          ## a `[str; N]` element as an argument
  std::io::print("\n")
  std::io::print("done\n")       ## POSITIVE CONTROL — a str LITERAL argument
  42
}
