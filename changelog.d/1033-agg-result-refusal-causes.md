- **`alatyr ir` names why an aggregate result keeps a function out of the shared IR (#1033).** Every
  such refusal used to read `signature: aggregate result wider than two words`, although the builder has
  taken results of up to eight words since #1026 and width was only one of the reasons. Each cause now has
  its own label: wider than eight words, no fields, a byte-layout struct, a generic struct, a struct field
  that is not a word scalar or is an array, a view, an enum or generic enum instance the register tier
  cannot lay out, a tuple, and a type that is really unresolved. What builds is unchanged; only the
  report of what does not, and so `scripts/ir_census.sh`'s ranking, moves.
