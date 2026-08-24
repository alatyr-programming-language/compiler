## TRUNCATED TAIL (I11 correct-or-trap; Grammar §2 — a program is a sequence of declarations, and the
## whole token stream belongs to one). The last declaration here has an unclosed parameter list, no
## body and no closing brace: a crashed editor, a partial copy or a bad merge. Every recursive-descent
## loop in `parser.al` terminates on the EOF sentinel as well as on its own closer (61 such guards), so
## the loop waiting for `)` stopped at end-of-input as if the group had closed and `parse_decl` returned
## a well-formed-looking Decl.
##
## MEASURED on the pre-fix compiler (f4456a4): `alatyr -o out <this>` exited 0 and the binary RAN to
## 42 — the truncated declaration and everything after it silently absent from the program that runs.
## `alatyr check` also returned 0. That is the forbidden outcome: the program that runs is not the
## program that was written.
##
## POST-FIX: the parser rejects at the outermost still-open opener, with the module name and the
## 1-based FILE line (line 21 here) in the located-reject shape `[module M, at line N, near `...`]`,
## on the build path AND the check path (build rc 1, check rc 1). Registered with `build_reject_has`
## in scripts/e2e.sh so a fail-loud accident cannot satisfy it.
main := fn() -> u64 {
  42
}

BROKEN := fn( -> u64 {
