## `hid::secret` is private and `main` is its SIBLING. The bare name is used as a VALUE, not called,
## so no callee check sees it; it must still be refused.
main := fn() -> u64 {
  f := secret
  f()
}
