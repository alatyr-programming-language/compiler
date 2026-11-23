- **After a `for`, `while` or `loop` that re-binds an enclosing local's name, the name denotes the
  enclosing local again (#1848).** `for v in 0..3 { … }` followed by `v + r`, with an outer
  `mut v : u64`, was refused as a mix of signedness because the checker still typed `v` as the loop
  variable; a binding declared in a `while` or `loop` body leaked the same way.
