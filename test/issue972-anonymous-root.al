## Issue #972 / Tooling §4 — the root file of a manifest-less invocation is the ANONYMOUS root module:
## it is excluded from module-path scanning, so its stem names no module and reaches no symbol. This
## file's stem is not an identifier, and it must not matter: `main` and `helper` emit unprefixed on all
## four backends, exactly as a `package.al` root's declarations do (Modules §6.1). Before the fix the
## stem was spliced into the labels, and `as` refused them on x86_64 and aarch64.
helper := fn(x : u64) -> u64 {
  return x + 2
}

main := fn() -> u64 {
  return helper(40)
}
## expect: run 42
