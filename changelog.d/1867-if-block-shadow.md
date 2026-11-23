- **A binding declared in a block no longer outlives the block in the checker when it shadows an
  enclosing local (#1867).** After `if c { v : u64 = 5 … }`, the statement `v = 42` assigns the
  enclosing `mut v` again instead of being refused as an immutable binding (Declarations §6.1). The
  same holds after an `unchecked { … }` block and an allocator block.
