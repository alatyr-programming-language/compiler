## §4 ABI / §8: MULTIPLE aggregate-value (struct-literal) arguments in one call. Each materializes into a
## DISTINCT agg-temp slice (bump allocator) and is passed by reference, so they no longer alias — this
## used to silently return 4 (both args saw the last literal). f(V2(30,10), V2(1,1)) = 30+10+1+1 = 42.
V2 := struct { x : u64, y : u64 }

f := fn(a : V2, b : V2) -> u64 {
  return a.x + a.y + b.x + b.y
}

main := fn() -> u64 {
  return f(V2(x = 30, y = 10), V2(x = 1, y = 1))
}
