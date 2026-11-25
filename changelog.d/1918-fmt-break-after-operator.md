- `alatyr fmt` now breaks an overflowing binary-operator chain after each operator, the operator ending
  the line and the next operand starting the continuation line one level in (#1918; Tooling §4.3.3,
  TOOL-28). It used to break before each operator. Under Grammar §2.6 (SYN-12) a line that begins with
  `-` starts a new statement, so the old layout split a `-` chain into separate statements.
