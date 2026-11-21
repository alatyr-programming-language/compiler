- x86_64: a struct literal with a niche-folded `Option(ptr(T))` field set to `Some(p)`, returned by
  value, kept its pointer. It was written as 0 and read back as `None` (#1688).
