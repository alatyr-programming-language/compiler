## e2e (DEEP-CHAIN field whole-assign of a MULTI-WORD struct final field). `o.mid.inner = <struct>`
## is a 2-hop field path (`FieldPathAssign`, base a nested `Field`). Its LOCAL fallback stored only
## WORD 0 of the final field, leaving the rest STALE — a Priority-1 silent miscompile (the deep-chain
## dual of the single-hop `FieldAssign` multi-word field store). Now a multi-word struct final field
## delivers ALL its words: here a struct LITERAL writes both words of `inner : Rec`; a scalar deep
## field (`o.mid.x`) keeps the byte-identical single-word store. `o.mid.inner.a + o.mid.inner.b` =
## `12 + 30` = 42.
Rec := struct { a : i64, b : i64 }
Mid := struct { inner : Rec, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  mut o : Outer = Outer(mid = Mid(inner = Rec(a = 0, b = 0), x = 0), tag = 7)
  o.mid.x = 99                          ## scalar deep field — single-word store (unchanged)
  o.mid.inner = Rec(a = 12, b = 30)     ## multi-word struct final field — ALL words delivered
  return u64(o.mid.inner.a + o.mid.inner.b)
}
