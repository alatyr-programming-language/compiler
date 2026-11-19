- The shared IR builder now builds a bare call `f(…)` when other modules also declare a function
  named `f` (#1772). It used to refuse every such call as an overload set, but an overload set
  is several functions in one scope (Functions §1.4), and a module binds a name only once
  (Modules §5). The call now means the function the calling module binds: its own declaration,
  or the one its import names (`f := M::f`, `(f, g) := M`). The builder takes it from the
  resolver x86's own call emission uses. On x86_64 that moves 51 more of the compiler's own
  functions, and the same shape in any multi-module program, from the legacy emitter to the IR.
  A bare name the calling module neither declares nor imports stays refused with a cause of its
  own, and so does a call into the module's own overload set.
