## BALANCED TRUNCATION IN THE MIDDLE OF THE FILE — the quietest member of the class, and the reason a
## tail-of-stream check is not sufficient. What is lost here is not a partial last line but every
## complete declaration that follows, `main` included.
##
## MEASURED on the pre-fix compiler (495e842): `alatyr check` returned 0 — it ACCEPTED a file whose
## `main` had vanished — and `alatyr -o out` exited 14 with a raw `ld` message,
## `undefined reference to reject_trunc_midfile_fn_no_body__main`. The only signal was a linker
## complaint about a symbol the author never wrote, with no source location. The mechanism: after the
## return arrow the parser scanned forward for the body's opening brace and, finding none on this line,
## kept going — straight over `main := fn() -> u64 {` — and took MAIN'S brace as this function's body.
## `main` was therefore never declared at all. The fix stops that scan at the `:=` that starts the next
## declaration (a return type never contains one) and then rejects, located.
##
## POST-FIX: build rc 1 and check rc 1, located at the truncated declaration.
BROKEN := fn() ->

main := fn() -> u64 {
  42
}
