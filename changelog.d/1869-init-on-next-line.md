- **A local whose `=` starts the next line is initialized (#1869).** `v : [u64; 2]` / `= [40, 2]` was
  taken for an uninitialized local: x86_64 laid out nothing (`v.len` answered 0), the other backends
  trapped, and an index read was refused at check. A line-leading `=` continues the declaration
  (Grammar §2.6, spec#172).
