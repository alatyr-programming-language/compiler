## e2e (#425) — CORRECT-OR-TRAP: an index BASE that names no frame slot is not a place the generic
## element-address tail can compose. `emit_index_addr`'s tail builds the element address as
## `slot + i * stride` out of the base's `SlotEntry`, and `index_base_entry` answered `0` — entry 0,
## the FIRST local of the frame — for every base it could not resolve. An ARRAY LITERAL used directly
## as a base has no frame home at all, so this program used to compile with rc 0 and emit
## `leaq -8(%rbp)` + `imulq $8`: it returned a word out of the CALLER's frame (0 here) instead of 42,
## a silent miscompile with no diagnostic.
##
## Grammar §3.4 makes `primary { postfix }` legal, so this spelling is well-formed and its correct
## lowering is a recognizer ABOVE the tail, not a wider default inside it. Until such a recognizer
## exists the tail refuses and names the source line. Sibling shapes that used to land in the same
## sink each carry their own issue: a range slice used directly as a base is #422.
##
## The working spelling is a bound local — `xs := [71, 42, 93]; xs[1]` — which every backend lowers.
## The diagnostic wording is asserted by the harness, not quoted here.
main := fn() -> u64 {
  [71, 42, 93][1]
}
