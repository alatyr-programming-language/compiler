- **A call's arguments are now judged against the declaration it names, wherever that declaration is
  written (#1746).** A module-qualified call `util::f(x)`, and an unqualified call to a function written
  after its caller, had their arguments checked against nothing: sema looked the callee up only among
  the declarations before the caller, and by a spelling a qualified name never matched. A struct passed
  to `x : u64` compiled and every backend answered a value read off the struct's bits. Module-level
  declarations are order-independent (Declarations §7.1), so the callee is now found among all of them,
  and a qualified `m::f` names `f` in module `m`. Such a call is refused with `type mismatch` at the
  argument, exactly as the same call to a function written earlier always was (Functions §2.2,
  Types §4.1, §4.3). No program in the test corpus changed its answer apart from the new fixtures.
- **A call through a local or parameter is no longer judged against a same-named module-level
  function.** `f(s)` for a parameter `f : fn(S) -> u64`, or `pick(s)` after `pick := g`, was refused
  with `type mismatch` when the module also declared `f(x : u64)` or `pick(x : u64)` above the caller,
  because the checker read the module-level function's parameters. The inner name wins within its
  scope (Declarations §6.1), so such a call now compiles and runs the bound function.
