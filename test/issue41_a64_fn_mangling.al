## Issue #41: a two-module qualified call must use module-qualified AArch64 symbols.
## The ambient std::probe module supplies the second module; the result is 42.
main := fn() -> u64 { return std::probe::answer() }
