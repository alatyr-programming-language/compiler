- **A call that leaves a parameter unbound, or passes too many arguments, is refused at `check`
  (#1822).** A statement call such as `g(1)` against `g := fn(a : u64, n : u64)`, an omitted `out`
  or `in out` parameter (#1466), a call to a function declared later in the module (the arity half of
  #1516), and a statement call with a surplus argument used to build or crash the compiler; the
  callee then read the missing parameter from whatever register held it, a silent wrong value or a
  crash. Each now fails with a located diagnostic naming the parameter (``the call leaves parameter
  `n` unbound``) or both counts. The value-position form, refused before as an `unbound name`, gets
  the same diagnostic. So does a call that omits its allocator parameter with no `alloc::with`
  around it (Functions §5.5 step 4; #1239 for the direct call); taking the caller's own allocator
  parameter as the ambient (step 2) is not implemented yet and is refused the same way (#1468), and
  so is an elided allocator in a struct literal, index, array literal, lambda body, field base or
  `deref` inside `alloc::with` (#1846), which was refused before as well. A call one argument short
  of a function with both an allocator parameter and a defaulted one (`dk(42)` against
  `dk := fn(ar : ptr(mut Arena), k : u64 = 7)`) may mean either; the specification does not say
  which yet (spec#171), so outside `alloc::with` it is refused rather than read in order, as it used
  to be (#1845 for inside). This is a patch: newly rejecting programs the specification declares
  invalid (Functions §2.3, §5.1), plus that one form it leaves undecided. An omitted `in` parameter
  with a default, and an allocator filled from an enclosing `alloc::with`, stay accepted. Generic,
  variadic, UFCS, overloaded and function-value callees are not judged yet (#1842, #1763), and a
  call in a `for` range bound or a `comptime if` arm is not reached (#1843). Binding an `out`
  parameter by projection is not implemented (#1702), so an omitted `out` is refused with the
  `in out` one.
