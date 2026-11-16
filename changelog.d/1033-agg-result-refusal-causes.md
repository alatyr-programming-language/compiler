- **`alatyr ir` names why an aggregate result keeps a function out of the shared IR (#1033).** Every
  such refusal used to read `signature: aggregate result wider than two words`, although the builder has
  taken results of up to eight words since #1026 and width was only one of the reasons. Each cause now has
  its own label. A struct result: wider than eight words, no fields, a byte-layout struct, a generic
  struct, or the first field the convention cannot take (a fixed array, a sub-word scalar, a brand or
  alias of a scalar, a float, or a type that is no scalar). Any other result: a view, a fixed array, an
  enum or generic enum instance the register tier cannot lay out, a tuple, a scalar reached only through
  a type alias, a float, a function type, `Never`, and a type that is really unresolved. What builds is
  unchanged; only the report of what does not, and so `scripts/ir_census.sh`'s ranking, moves.
