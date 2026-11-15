- **The shared IR builds a niche-folded `Option(ptr(T))` — one pointer word, no discriminant
  (#1576).** A local of that type, a parameter and argument, a result and a call to such a function,
  and a `match` over one are now built from the IR. Before, the builder refused every one of them — a
  parameter was `signature: parameter type names no struct or enum resolvable here`, a result
  `signature: aggregate result wider than two words` — and the legacy emitters that took them over
  trapped on aarch64 and riscv64 and crashed wasm. `Option(ptr(T))` is exactly pointer-width (Types
  §6.2/§8, Memory §4.2): `None` is the payload's null pattern and `Some(p)` is the pointer itself, so
  a `match` tests that one word against zero and the absent case writes it. It crosses a call as every
  aggregate does — in as the address of a caller-owned copy, out as one word in the result register —
  which is the convention each legacy emitter already uses, so an IR-built function and a legacy one
  exchange folded options in both directions. An `Option` or `Result` over a struct, an enum, a slice
  or a `bool` payload is not built yet and keeps its located refusal.
