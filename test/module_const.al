## e2e — MODULE-LEVEL scalar constants (`NAME := <compile-time value>`, Memory §: module data is
## initialized with a compile-time-known value). A `Var` use of such a name emits the value inline
## (no runtime storage) rather than reading an unbound frame slot (which returned 0). Constants
## compose in expressions. Returns 42 = 6 * 7.
WIDTH := 6
HEIGHT := 7
main := fn() -> u64 {
  WIDTH * HEIGHT
}
