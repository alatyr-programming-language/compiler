- **The shared IR builds a niche-folded `Option(ptr(T))` — one pointer word, no discriminant
  (#1576).** A local of that type, a parameter and argument, a result and a call to such a function,
  and a `match` over one are now built from the IR. Before, the builder refused every one of them —
  a parameter was `signature: parameter type names no struct or enum resolvable here`, a result
  `signature: aggregate result wider than two words` — and the legacy emitter took them over.
  `Option(ptr(T))` is exactly pointer-width (Types §6.2/§7, Memory §4.2): `None` is the payload's
  null pattern and `Some(p)` is the pointer itself, so a `match` tests that one word against zero and
  the absent case writes it. On x86_64 it crosses a call as every aggregate does — in as the address
  of a caller-owned copy, out as one word in the result register — which is the convention x86_64's
  legacy emitter already uses, so an IR-built function and a legacy one exchange folded options in both
  directions there at the same value (measured 42 on the default, `x86-legacy` and `x86-ir` plans).
  The aarch64, riscv64 and wasm selectors keep such a signature, and every call to one, on the legacy
  emitter (`ir::sig_pins_legacy`): theirs reads an aggregate parameter's payload at `[#8]`, the
  unfolded tag and payload pair, a different shape from the folded word. A folded option whose signature
  mentions none — a local read with `match` — is IR-built there too, and that moves a value: where the
  parent refused it and each of those legacy emitters trapped (`unsupported match statement`, 133 on
  aarch64 and riscv64; `unreachable`, 134, on wasm), all four backends now answer 42. An `Option` or
  `Result` over a struct, an enum, a slice or a `bool` payload is not built yet and keeps its located
  refusal.
