- **An `@inline` comptime-variadic call answers the pack, not just the tail (#1681).** A callee marked
  `@inline` whose last parameter is a bare `...` rest is expanded at its call site by both markers:
  Codegen §3.5 (CG-10) substitutes the body with no `call`, and Functions §7.1 monomorphizes it over
  the trailing arguments, which form the comptime pack its `comptime for` walks. The call site chose the
  `@inline` expander, and that expander binds every parameter as an ordinary value — it never handed the
  pack over, so the loop unrolled zero times and only the body's final expression survived:
  `@inline sum := fn(args : ...) -> u64 { mut t : u64 = 0; comptime for a in args { t = t + a }; t + 2`
  `}` with `sum(20, 20)` answered 2 where 42 was due, on the default, `x86-legacy` and `x86-ir` plans
  alike. A comptime-variadic callee now goes to the variadic expander, which threads the pack and still
  emits no `call`, so both contracts hold; a plain `@inline` callee keeps its own expander unchanged.
