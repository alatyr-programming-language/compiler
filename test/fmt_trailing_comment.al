## #1178 — `alatyr fmt` deleted every comment after the LAST top-level declaration.
## Tooling §4.3.4: comments are "preserved verbatim", and "`fmt` never deletes, merges, or
## rewrites the content of a comment". A comment ABOVE or BETWEEN declarations was kept, because
## `emit_fmt_program` emits each declaration's LEADING comments and nothing after the last one;
## a comment at the end of the file had no declaration to be leading, so it was dropped.
## `scripts/e2e.sh`'s `fmt_test` already counts `##` lines in the source and in the formatted
## output (idempotence alone is also satisfied by deleting them), so this fixture fails before
## the fix with `comments N want M` and passes after it. No fmt fixture ended with a comment
## before this one, which is why 41 fmt rows stayed green over the defect.
## expect: run 42
answer := fn() -> u64 {
  return 42
}

## Program entry: reads the helper, so the exit code is the answer.
main := fn() -> u64 {
  return answer()
}

## Trailing comment after the last declaration — deleted before #1178.
## A second trailing line, stacked with the one above it — also deleted before #1178.

## And one more after a blank line, so the flush is not only a stacked block.
