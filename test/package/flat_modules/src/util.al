## A SUBMODULE of the default-source package: its declarations keep the ordinary `<module>__<fn>` mangling
## (`util__answer`) — unprefixing is the ROOT module's rule alone (Modules §6.1). `answer` is `pub`
## because its caller `main` is a SIBLING module, not a descendant: Modules §3 exposes a declaration
## upward only through `pub`. (This fixture called it without `pub` until 2026-08-20, when §3 stopped
## being enforced for module globals alone.)
pub answer := fn() -> u64 {
  return 42
}
