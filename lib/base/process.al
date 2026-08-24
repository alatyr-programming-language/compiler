## `exit(code)` — terminate the process with status `code` (Stdlib §4.2). The
## clean-shutdown primitive: result `Never`, so a call is a flow terminator
## (§3.7). This first stdlib implementation covers the target surface the
## compiler can actually lower today: raw Linux x86_64. Linux x86_64's
## process-wide primitive is `exit_group`, syscall number 231; number 60 is
## the thread-local `exit` and is wrong for a hosted process with threads.
##
## The integer is OS/arch target data, not a language contract (ABI §5/FN-9).
## Keep the public wrapper guarded until another target has a real syscall
## lowering; an unsupported target must fail loudly (diagnostic or target trap)
## rather than silently emitting an x86 syscall shape. The current parser's
## bodyless `@abi(syscall)` form has no `when` tail, so the declaration stays
## internal and is reached only through the guarded wrapper.
sys_exit_group := @abi(syscall) fn(num : usize, code : usize) -> Never

exit := fn(code : usize) -> Never when target.arch == Arch.x86_64 and target.os == Os.linux {
  unchecked sys_exit_group(231, code)
}
