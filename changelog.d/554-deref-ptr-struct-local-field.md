- **`deref(ptr(loc)).field` on a struct local reads the field (#554).** On x86_64 the read
  contributed nothing: `40 + deref(ptr(loc)).b` answered 40 where `loc.b` answered 101 in the same
  program, with a clean compile and no diagnostic. Memory §4.3 makes `ptr` and `deref` inverse on a
  memory-resident place, so the expression is the field read itself. It now reads the field at its
  byte offset with its own width and sign, for narrow-field and `@packed` structs as well as
  word-sized ones; reading a whole struct, `str` or payload-carrying enum field this way is refused
  with a located diagnostic instead of copying one word of it. aarch64, riscv64 and wasm still stop
  at their field-access stub there (#1187), a trap rather than a value.
