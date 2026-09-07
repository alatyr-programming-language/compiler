## e2e (#495) — CORRECT-OR-TRAP: a MODULE-LEVEL ARRAY global whose FIRST element is a `str` but whose
## later elements are not. Element 0 fixes the `.data` element stride, and a `str` element is a
## two-word `{ptr, len}` cell (Types §7) while a scalar element is one word, so imaging this array
## would place every element after the first at an offset the strided read does not use — the picture
## and the reader would silently disagree.
##
## FAILURE-FIRST: on the parent this program compiled with rc 0 and every element imaged as one
## `.quad 0`, because a str literal has no scalar init value; the array was uniformly useless rather
## than mis-strided, so nothing complained. #495 gives the str-element array a real 2-word image, so
## the mixed spelling now has to be refused rather than imaged at two different widths.
##
## Sema accepts a mixed array literal today, which is why this guard stands in the emitter instead of
## being assumed unreachable. The refusal comes from IMAGING the global, so the body does not read it:
## reading a global str element is the shape #495 fixes and the parent refused that read on its own,
## which would have made the fixture pass for the wrong reason. With no read present the parent
## compiles with rc 0. The diagnostic wording is asserted by the harness, not quoted here.
G := ["abc", 7]
main := fn() -> u64 {
  7
}
