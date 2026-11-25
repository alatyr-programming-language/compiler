- **`X : u64 = m::X + 1` beside a module `m` that declares its own `X` builds (#1567).** On x86_64
  the qualified `m::X` was answered from a cache entry of the bare `X`, and the compiler chased the
  initializer until it crashed (SIGSEGV).
