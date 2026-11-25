- **An index read over a `Vec` of a struct another module also names reads the right struct (#1829).**
  `v[i].b` over `Vec(Node)` compiled to the constant 0 on x86_64 once any other module of the package
  declared a `Node`. The bare element type now resolves to the declaration of the module that spells
  it, else its nearest ancestor's (Declarations §5, MOD-16).
