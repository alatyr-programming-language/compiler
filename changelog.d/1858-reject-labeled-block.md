- **A labeled block `@label(name) { … }` is refused, located, instead of losing its body (#1858).**
  Its statements were silently dropped on every backend. Until labeled blocks are implemented the
  compiler names the label and the issue; labeled `loop`, `while` and `for` are unchanged.
