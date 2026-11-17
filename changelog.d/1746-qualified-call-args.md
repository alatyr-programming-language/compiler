- **A call's arguments are now judged against the declaration it names, wherever that declaration is
  written (#1746).** A module-qualified call `util::f(x)`, and an unqualified call to a function written
  after its caller, had their arguments checked against nothing: sema looked the callee up only among
  the declarations before the caller, and by a spelling a qualified name never matched. A struct passed
  to `x : u64` compiled and every backend answered a value read off the struct's bits. Module-level
  declarations are order-independent (Declarations §7.1), so the callee is now found among all of them,
  and a qualified `m::f` names `f` in module `m`. Such a call is refused with `type mismatch` at the
  argument, exactly as the same call to a function written earlier always was (Functions §2.2,
  Types §4.1, §4.3). No program in the test corpus changed its answer apart from the new fixtures.
