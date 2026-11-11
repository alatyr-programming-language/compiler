- **x86_64 emits from the shared IR by default (#980).** Every function the IR builder builds, the
  verifier accepts and the selector selects is now emitted from the IR on every x86 surface, the
  compiler's own build included; the rest keep the legacy emitter. The twins already did. Programs the
  legacy emitter refused or answered wrongly now run and answer what aarch64, riscv64 and wasm answer:
  a struct variable or enum stored into a deep field (42), a `@packed` struct inside a plain one (20),
  two same-named locals of different types in different scopes (109, #406). A `match` whose value is
  no variant now traps instead of yielding -1 (#1579). Functions the builder does not yet build keep
  the legacy emitter and its answers: an array copied from a by-value array parameter or a struct's
  array field (#937), and range slices over `[u16; N]`-style arrays handed to a callee (#1514).
  `alatyr x86-legacy <file>` emits with the legacy emitter alone; `alatyr x86-ir` still works and
  spells out the default. A function the IR verifier refuses is a located internal error (exit 70) on
  the default surface, as it was under `x86-ir`.
