## e2e (P2 ambient stdlib injection): this program calls a stdlib function by its 3-segment path
## `std::probe::answer` WITHOUT listing the module — the compiler discovers its shipped `lib/`, scans
## this source for `std::…::…` / `alloc::…::…` references, and ambiently injects `lib/std/probe.al`
## (module `std__probe`, so the call resolves to the `std__probe__answer` label). Expected exit: 42.
main := fn() -> u64 { return std::probe::answer() }
