# Standard-library surface contract

The standard library is tiered. `base` contains language-defined values and
pure helpers, `alloc` requires an explicit arena, and `std` is the Linux
x86_64 OS-facing tier. A module is part of the public surface only when its
platform assumptions, ownership rules, and failure behavior are documented.

## v1 modules

| Module | Tier | Surface |
| --- | --- | --- |
| `std::argv` | std | Borrowed command-line segments read from the process at call time. |
| `std::env` | std | Not a separate module; use the documented `std::os` environment readers. |
| `std::io` | std | File-descriptor I/O and `Result(_, IoError)`. |
| `std::os` | std | Linux process input, files, and explicit arena-backed OS memory. |
| `std::term` | std | Standard output/error streams and fallible writes. |
| `std::time` | std | Linux clock reads. |
| `std::net` | — | Not shipped in v1. Networking needs an explicit socket, ownership, blocking, and ABI decision. |

The `std::argv` and `std::term` additions are intentionally small. They give
applications named entry points without hiding allocation or turning a Linux
syscall into a portable guarantee. `std::argv` returns views into caller-owned
storage; an out-of-range index is an empty view. The wrapper does not allocate,
so it has no hidden OOM path. `std::term::write` reports `IoError` and may return
a short write; callers decide whether to retry.

## Error and ownership rules

Fallible OS operations return a concrete `Result` and map unclassified errno
values to `IoError::Other`. Borrowed slices remain valid only while the caller's
buffer or arena remains live. No module creates process-global mutable storage,
and no API claims to be available under the `freestanding` limit.

## Deliberate exclusion

There is no `std::net` module in the current specification. Adding one without
deciding socket address representation, blocking and timeout semantics,
ownership/close behavior, and per-target ABI would create an attractive but
non-portable API. The release and target documents record this as an explicit
v1 exclusion rather than silently exposing an incomplete implementation.
