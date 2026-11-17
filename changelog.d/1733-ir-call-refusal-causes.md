- `alatyr ir` names the cause of a refused call instead of reporting `expr Call` for all of them
  (#1733): `call: generic callee`, `call: several functions of that name`, `call: built-in or intrinsic
  callee`, `call: extern callee`, `call: more than eight arguments` and the other `call: …` labels, one per
  cause, so the IR census ranks them. Which functions build, and what they build to, is unchanged.
