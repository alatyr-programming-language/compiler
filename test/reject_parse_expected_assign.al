## ROADMAP §5 — the PARSE diagnostic now renders the EXPECTED token kind from `ParseErr`
## ("(expected `:=`)"), reachable since a returned `Result(_, ParseErr).Err(e)` delivers its
## multi-word enum payload whole. After the declaration name the parser expects `:=` (kind 5);
## `bar` is not it → the located diagnostic names the expectation. The error is on line 7.
main := fn() -> u64 { return 42 }

foo bar
