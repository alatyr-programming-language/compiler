## e2e (P3 ambient stdlib — a REAL shipped function, not the probe canary): this program calls
## `std::io::print` by its 3-segment path WITHOUT listing any module. The compiler discovers its
## shipped `lib/`, injects `lib/std/io.al` (module `std__io`) AND the base-tier prelude closure
## (`assert`/`result`/`option`/`alloc`, which `io` rests on), then builds + links + runs it. `print`
## writes the bytes to stdout via a real `write(2)` syscall and returns the byte count. The string
## is 15 bytes ("ambient stdlib\n"); a correct write returns 15 → this exits 42. (Proves the whole
## ambient path end to end: discovery, injection, cross-module lowering, the str→`[u8]` `bytes`
## view, the slice-param `.ptr`/`.len` read, and the syscall — not just that it compiles.)
main := fn() -> u64 {
  n := std::io::print("ambient stdlib\n")
  if n == 15 { return 42 }
  1
}
