## BALANCED TRUNCATION IN THE MIDDLE OF THE FILE — a `match` whose braced arm list never opens.
##
## MEASURED on the pre-fix compiler (495e842): `alatyr check` returned 0 and `alatyr -o out` exited 14
## with `undefined reference to reject_trunc_midfile_match_no_arms__main` from `ld` — `main` had been
## swallowed whole. The subject expression parsed as `main`, the brace that should have followed was
## skipped unconditionally, and the arm loop then consumed the rest of the program as arms.
##
## POST-FIX: build rc 1 and check rc 1, located, naming the arm list that never opened.
BROKEN := match

main := fn() -> u64 {
  42
}
