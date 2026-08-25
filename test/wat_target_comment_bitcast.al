## Issue #44 safety residual: target-type comments are not source delimiters. A fake closing bracket in
## a `bitcast` target comment must not let the global alias enter scalar named-value admission.
## Failure-first baseline on amendment parent PR #77 HEAD 9dea57583aafa9e2362751a0324b42e853685d2b:
## x86_64=4, WAT=4. After the fix x86_64 remains 4 while WAT must fail-loud with 134.
G := bitcast(
  ## fake unmatched close ) in target comment
  ptr(u64),
  4
)

main := fn() -> u64 {
  x := @label(outer) loop {
    loop {
      break outer G
    }
    break 0
  }
  x
}
