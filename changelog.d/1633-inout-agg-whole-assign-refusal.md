- **A whole `p = v` into an `out` / `in out` struct or enum parameter is refused on every backend
  (#1633).** No legacy emitter wrote it back to the caller's place (Functions §2.1, §4.1): aarch64,
  riscv64 and wasm answered the caller's old value, and x86_64 refused it only through an unrelated
  slot-width check. It is now one located refusal, shared by the four legacy emitters, until the shared
  IR builds the store. A bare `ptr(mut P)` is no longer taken by the IR as an `in out P` place (#1635).
