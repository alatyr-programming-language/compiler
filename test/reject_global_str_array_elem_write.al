## e2e (#495) — CORRECT-OR-TRAP: a whole-element WRITE to a MODULE-LEVEL `[str; N]` global. Each
## element is a two-word `{ptr, len}` cell (Types §7) at a 2-word stride, and the only store arm that
## could claim this shape is the SCALAR one, which puts a single word at `LABEL + i*8`: for `G[1] = …`
## that is element 0's LENGTH word, so the write lands inside a NEIGHBOURING element and the element
## it named is left untouched.
##
## FAILURE-FIRST: on the parent this program compiled with rc 0. The corruption was MASKED there
## because no element read worked either — every element imaged as one `.quad 0`, so a read answered
## an empty view, trapped, or was refused. #495 makes the READ correct, which would have turned the
## broken store into a plausible-looking wrong byte (the #421 hazard) instead of a loud failure, so
## the store is refused until it gets a correct 2-word arm of its own.
##
## The body deliberately does NOT read the array back: the read of a global str element is itself the
## shape #495 fixes, and on the parent it was already refused, so a fixture that read it would have
## been rejected for the OTHER reason and proved nothing about the store. With only the store present
## the parent compiles with rc 0 and this tree names the store's own line.
##
## The working spelling is a LOCAL `[str; N]`, whose whole-element write every backend lowers.
## The diagnostic wording is asserted by the harness, not quoted here.
mut G : [str; 2] = ["abc", "XYZ"]
main := fn() -> u64 {
  G[1] = "wxyz"
  7
}
