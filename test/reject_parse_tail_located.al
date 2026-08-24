## A parse failure must carry its POSITION on every CLI path, not only under `check`.
##
## `parser::parse_program` returns `Result(usize, ParseErr)` and `ParseErr` is `enum { Expected(u8),
## Eof }` — the expected token kind and NOTHING else. No span, no line, no module. The position lives
## in the `PC` the failed parse leaves behind, and `driver::check_files` was the only caller that read
## it back; ten other call sites collapsed the `Err` into `panic("selfhost: parse error")` — 21 bytes,
## no file, no line, no module — on the `-o` build, `run`, `test`, `fmt` and bare-GAS-emit paths. Two
## lanes stopped using the channel and reported through `parser::reject_at` instead.
##
## The assertion is on the POSITION, not on the rejection. A regression that keeps the non-zero exit
## and drops the location must FAIL this row, which a bare `build_reject` could never notice: the
## registered needle names the source line the trailing comma sits on AND this module's own name.
##
## The program below the comment is COMPLETE and returns 42; delete the final declaration and it
## builds and runs. So the reject, and its line number, can only come from that one line — this is the
## shape the defect was reported on, a real typo at the tail of a file the author believes is intact,
## not a file that is garbage from its first token.
main := fn() -> u64 {
  42
}
x := 1,
