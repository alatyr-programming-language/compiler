- A line that begins with `-`, `(`, `[` or `..` no longer continues the previous line (#1910; Grammar
  §2.6, SYN-12): those tokens are not continuing tokens, so the line starts a new statement. The
  parser used to read `return a` followed by a line `- 8` as `return a - 8`, `g` followed by a line
  `(42)` as a call, and a line `[0]` as an index of the expression before it. Inside `( … )` and
  `[ … ]` newlines stay free. A `for` header or a `match` arm pattern whose range `..` starts the next
  line is now refused, located, because the header or pattern before it is incomplete.
