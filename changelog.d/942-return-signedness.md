- **Returning an integer of the other signedness is a compile error (#942).** `fn() -> u64` that
  returned an `i64` local, for example `a := 0` then `return a - 1`, compiled and answered
  `2^64 - 1` on x86_64. Signed↔unsigned is a numeric conversion, and Types §4.3 makes it explicit. A
  `return` and a fn's tail are now refused at the returned value with their own diagnostic. That
  includes an untyped module constant: `K := 42` is an `i64`, so returning it from `-> u64` is refused.
  Write `u64(v)`, or declare the binding with the type it is returned as. A literal still takes the
  declared result's type. Three result sinks are not checked yet (#1348): a `return` inside
  `comptime if`, a `match`-expression tail, and a generic `-> T` returning an inferred local.
  Arguments, assignments and width follow in later slices of #942.
