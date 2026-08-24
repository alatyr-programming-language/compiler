## §4 ABI / §8: NESTED aggregate-value args — a struct-literal arg alongside a struct-RETURNING call that
## itself takes a struct-literal arg. The agg-temp bump pointer is save/restored per call, so the inner
## call's temp stacks above the outer's still-live literal (no clobber). sum2(V2(20,10), mk(V2(5,5))) =
## 20+10 + (5+1)+(5+1) = 42.
V2 := struct { x : u64, y : u64 }

mk := fn(p : V2) -> V2 {
  return V2(x = p.x + 1, y = p.y + 1)
}

sum2 := fn(a : V2, b : V2) -> u64 {
  return a.x + a.y + b.x + b.y
}

main := fn() -> u64 {
  return sum2(V2(x = 20, y = 10), mk(V2(x = 5, y = 5)))
}
