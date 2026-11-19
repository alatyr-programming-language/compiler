- The shared IR builder now builds a call spelled with a module path (`m::f(…)`) when the
  rest of the call is in its subset (#1744). It takes the callee from the resolver x86's own
  call emission uses. On x86_64 that moves more functions of the compiler's own build, and of
  any multi-module program, from the legacy emitter to the IR. Three kinds of callee are still
  refused, each with a named cause: an overload set, a generic, and a callee from another
  module whose signature reaches a type name declared more than once (through an alias, a
  field or a variant payload too). On aarch64, riscv64 and wasm, a module-path call whose
  module was dropped because two functions would share a bare label (#41) stays refused, so
  it keeps its trap rather than calling the caller's same-named function.
