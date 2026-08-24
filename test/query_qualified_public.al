good_resolve := resolves(std::probe::answer())
good_compile := compiles(std::probe::answer())
bad_resolve := resolves(std::probe::missing())
main := fn() -> u64 {
  if good_resolve {
    if good_compile {
      if bad_resolve { 1 } else { 42 }
    } else { 2 }
  } else { 3 }
}
