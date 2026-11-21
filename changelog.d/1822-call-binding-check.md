- **A call that leaves a parameter unbound, or passes too many arguments, is refused at `check`
  (#1822, #1466, #1516).** A statement call such as `g(1)` against `g := fn(a : u64, n : u64)`, a
  call to a function declared later in the module, and a call with a surplus argument all used to
  build; the callee then read the missing parameter from whatever register held it, a silent wrong
  value or a crash. Each now fails with a located diagnostic naming the parameter (``the call leaves
  parameter `n` unbound``) or both counts. The value-position form, refused before as an `unbound
  name`, gets the same diagnostic. This is a patch: newly rejecting programs the specification
  declares invalid (Functions §2.3, §5.1). An omitted `in` parameter with a default and an elided
  allocator (MEM-5) stay accepted; generic, variadic, overloaded and function-value callees are not
  judged yet. Binding an `out` parameter by projection is not implemented (#1702), so an omitted
  `out` is refused with the `in out` one.
