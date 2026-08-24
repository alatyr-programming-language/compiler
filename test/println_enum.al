## e2e — the STD-tier `std::fmt::println` composing over the alloc-tier ENUM display arm (
## Stdlib §2.7; enum rendering via the comptime variant match). `println(Opt, Opt.Just(5))`
## builds a StrBuf via `display` (rendering the enum as `Just(5)`), appends a newline, and writes it
## to stdout with a real `write(2)` syscall, returning the byte count. `Just(5)\n` is 8 bytes, so a
## correct render+write returns 8 → this exits 42. Proves the whole ambient path over an enum:
## discovery + transitive injection (std/fmt → alloc/fmt → alloc/strbuf → std/os …), the enum
## `Enum(_)` arm (variant name + payload), and the std-tier write — the path a user actually calls.
Opt := enum { Nothing, Just(u64) }

main := fn() -> u64 {
  n := std::fmt::println(Opt, Opt.Just(5))
  if n == 8 { return 42 }
  1
}
