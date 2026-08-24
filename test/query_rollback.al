## A failed capability-query attempt is private: nested semantic diagnostics must roll back and
## become the query's `false`, not poison the enclosing function.
S := struct { x : u64 }
sink := fn(x : u64) -> u64 { x }
outer := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  bad_compile := compiles(outer(sink(S(x = 1))))
  bad_resolve := resolves(outer(sink(S(x = 1))))
  if bad_compile or bad_resolve { 41 } else { 42 }
}
