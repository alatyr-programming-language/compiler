## e2e (COMPTIME TYPE DISPATCH — `comptime if (match typeinfo(T) { <Kind>(_) => … })` folded by T's
## KIND). The second piece of the comptime evaluator: inside a monomorphized instance the concrete
## type of `T` is known, so `match typeinfo(T)` folds to the arm for T's kind (struct / enum / array /
## scalar) and only that branch is emitted. This is exactly `base/derive`'s type-dispatch cascade.
## Here `pick(u64, 42)` is a SCALAR → falls through struct/enum/array to the `else` (`u64(v)` = 42);
## `pick(Pt, …)` is a STRUCT → the struct arm (100). 42 + 100 - 100 = 42.
Pt := struct { x : u64, y : u64 }
pick := fn(T : type, v : T) -> u64 {
  comptime if (match typeinfo(T) { Struct(_) => true; _ => false }) { return 100 }
  else {
    comptime if (match typeinfo(T) { Enum(_) => true; _ => false }) { return 200 }
    else {
      comptime if (match typeinfo(T) { Array(_) => true; _ => false }) { return 300 }
      else { return u64(v) }
    }
  }
}
main := fn() -> u64 {
  s : u64 = 42
  pick(u64, s) + pick(Pt, Pt(x = 1, y = 2)) - 100
}
