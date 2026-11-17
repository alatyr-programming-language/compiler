- **The shared IR builds a generic enum instance whose payload is a struct or an enum (#1033).**
  `Option(P)`, `Result(u64, E)` and `Option(Option(u64))` were refused as results, locals, parameters
  and payloads with the label "generic enum instance result the builder cannot lay out". The builder
  now lays such a payload out as a sub-object at the offset and size the layout authority gives
  (`lower_layout::enum_layout`, `agg_words`): it builds it in place in a variant literal, copies it
  out at a `match` binding, and passes an enum error through `?` unconverted. A payload whose type is a
  brand, a required type or an alias over a scalar takes sema's kernel type for that name. On aarch64,
  riscv64 and wasm, whose legacy emitters lay these instances out differently, a function whose
  signature carries one stays legacy, as does every call to it.
