## focused review control — the same invalid Slice(str) element must reject on the stack-argument path.
take_many := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64) -> u64 { g }

bad := fn(s : Slice(str)) -> u64 {
  take_many(0, 0, 0, 0, 0, 0, s[0])
}

main := fn() -> u64 {
  bad(Slice(str)(ptr = unchecked bitcast(ptr(str), 0), len = 0))
}
