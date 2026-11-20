- The shared IR now builds the `bitcast` crossing between a pointer and a register-width integer, in
  **either direction**, as one word carried unchanged (`OpBits` at the width the two types share): reading
  an address out as a `usize`, and fabricating a `ptr(T)` from one (#980; Types §4.2's `reinterpret` row
  and §4.4, Memory §4.5, ABI §6 one integer register class). Each of the four selectors moves the word.
  The builder builds the crossing only inside an `unchecked` grant, as Memory §4.5 requires, although
  `check` does not yet refuse the ungranted form (#1780). `v1_conv`'s `OpBits` rule admits exactly one
  side being a pointer and refuses a float against a pointer. A width that differs (ill-formed, Types
  §4.4; still accepted by `check`, #1747) and a float against a pointer stay refused at the `bitcast`.
  On the emit path a function now selected from the IR on every backend is one that fabricates a pointer
  to a user type (`bitcast(ptr(S), a)`). A word-scalar or `ptr(<scalar>)` target is still erased into
  its operand at every emit entry while sema's record stays the target's (#1781), so such a
  function stays with the legacy emitter, which already lowers it; `alatyr ir` shows the builder's rule
  for those.
