- **`deref(ptr(loc)).field` on a struct local reads the field (#554).** On x86_64 the read
  contributed nothing: `40 + deref(ptr(loc)).b` answered 40 where `loc.b` answered 101 in the same
  program, with a clean compile and no diagnostic. Memory §4.3 makes `ptr` and `deref` inverse on a
  memory-resident place, so the expression is the field read itself, and it now emits the same field
  load as `loc.b`. aarch64, riscv64 and wasm still stop at their field-access stub there (#1187), a
  trap rather than a value.
