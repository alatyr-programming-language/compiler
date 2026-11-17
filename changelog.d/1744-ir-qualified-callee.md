- The shared IR builder now builds a call spelled with a module path (`m::f(…)`) when the
  rest of the call is in its subset (#1744). It takes the callee from the resolver x86's own
  call emission uses. On x86_64 that moves more functions of the compiler's own build, and of
  any multi-module program, from the legacy emitter to the IR. Three kinds of callee are still
  refused, each with a named cause: an overload set, a generic, and a callee from another
  module whose signature names a type declared more than once.
