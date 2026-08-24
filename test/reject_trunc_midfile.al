## TRUNCATION IN THE MIDDLE of the file, not at its end — the worst case of the class, because what is
## dropped is not a partial tail but EVERY complete declaration that follows, `main` included. The
## unclosed parameter list on line 14 swallows the rest of the token stream, so the program the
## compiler assembles has no entry point at all.
##
## MEASURED on the pre-fix compiler (f4456a4): `alatyr check` returned 0 — it ACCEPTED a file whose
## `main` had vanished — and `alatyr -o out` exited 14 with a raw `ld` undefined-reference error about
## `main__main`, i.e. the only signal was a linker message about a symbol the author never wrote, with
## no source location and nothing pointing at the truncation. Identical to the failure an EMPTY file
## produces, which is exactly the point: the compiler could not tell the two apart.
##
## POST-FIX: a located parser reject at the unclosed `(` (line 14), build rc 1 and check rc 1 — the
## diagnostic names the line where the file stops being the program the author wrote.
BROKEN := fn( -> u64 {

main := fn() -> u64 {
  42
}
