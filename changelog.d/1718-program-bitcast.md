- **A program that declares `bitcast` calls its own declaration (#1718).** `bitcast(10, 2) + 32`
  beside `bitcast := fn(a : u64, b : u64) -> u64 { a }` answered 34 on every backend, the call parsed
  as the prelude's reinterpret; the zero- and one-argument declared forms were refused at parse time.
  A call written `bitcast(T, v)` with a type first is still the reinterpret (Declarations §6.1).
