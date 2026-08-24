## std::thread — OS threads over the raw `clone` syscall (Concurrency CC-1 / CC-7).
##
## The language ships PRIMITIVES only (CC-1): a thread comes from the OS via a raw
## `clone(2)`, not from a language-managed runtime — no hidden scheduler, no libc, no
## allocator dependency (I3). This module is the v1 threading surface: `spawn` maps a
## fresh stack, `clone`s a joinable thread that runs a fn pointer, and returns a `Thread`
## handle; `join` futex-waits the thread out and reclaims the stack. It is absent under
## the `freestanding` limit and is x86_64-only in v1 (the naked trampoline is x86_64 GAS).
##
## THAT "x86_64-only" IS NOW SPELLED IN THE SOURCE. `spawn_raw`, `spawn` and `join` each carry a
## `when target.arch == Arch.x86_64` DECLARATION GUARD (Comptime §7.1/§9, CT-5; Tooling §2.7 — the
## typical use of `target.*`), so on any other target the three are AS IF ABSENT rather than emitted.
## Without the guard the trampoline's raw GAS went straight to the assembler on every backend — raw
## `asm(…)` is "validated only by `as`" (Assembly §4), so `movq %rdi, %r12` in an aarch64 or RISC-V
## object was an `unknown mnemonic` reject, and the wat backend emitted an x86 instruction stream into
## a WASM module. Absent is the honest state: a program that calls `thread::spawn` on a target with no
## trampoline gets an UNRESOLVED NAME — a diagnostic at the call, not a dead mnemonic at the assembler.
## Adding a target is adding a guarded trampoline beside this one, not editing this one.
##
## `spawn`/`join` are guarded too, not just `spawn_raw`: their bodies pass RAW x86_64 SYSCALL NUMBERS
## (`mmap` 9 / `munmap` 11 / `futex` 202 — see below), which name different calls on aarch64 (222 /
## 215 / 98) and riscv64. They are x86_64 code in exactly the same sense the trampoline is.
##
## The whole clone/child path lives in ONE `@abi(naked)` trampoline (`spawn_raw`) — the
## child cannot use a plain `@abi(syscall)` wrapper because after `clone` the child would
## `ret` off a brand-new empty stack; it must instead `call` the worker fn pointer and
## then `exit` the thread. Everything else (mmap the stack, arm the join word, bookkeeping,
## futex-join, munmap) is ordinary Alatyr around that trampoline.

## The Linux syscalls this module needs (raw x86_64 numbers, no libc; ABI §5). A
## negative return is `-errno`; callers wrap the traps in `unchecked` (raw level, I11).
##   mmap  = 9   munmap = 11   futex = 202
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
sys_munmap := @abi(syscall) fn(num : usize, addr : usize, len : usize) -> isize
sys_futex := @abi(syscall) fn(num : usize, uaddr : usize, op : usize, val : usize, timeout : usize, uaddr2 : usize, val3 : usize) -> isize

## The raw `clone` trampoline (spec ch.80 — a naked fn; Concurrency §9.2). Translated nearly
## line-for-line from a verified GAS spawn. SysV args: fn_ptr=%rdi, arg=%rsi, stack_top=%rdx,
## ctid=%rcx. They are moved into the callee-saved / clone-arg registers FIRST (r12/r13 survive
## the `syscall` clobber AND are copied into the child), then `clone(flags, stack, 0, &ctid, 0)`.
## Parent path: `clone` returns the child tid in %rax → `ret`. Child path (%rax == 0): load the
## saved arg into %rdi, `call` the worker through %r12, then `exit(0)` — the thread exit makes the
## kernel clear the CHILD_CLEARTID word and FUTEX_WAKE the joiner.
## FLAGS 0x1250f00 = VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|CHILD_CLEARTID|CHILD_SETTID (a joinable thread).
spawn_raw := @abi(naked) fn(fn_ptr : usize, arg : usize, stack_top : usize, ctid : usize) -> isize when target.arch == Arch.x86_64 {
  asm("movq %rdi, %r12")
  asm("movq %rsi, %r13")
  asm("movq %rcx, %r10")
  asm("movq %rdx, %rsi")
  asm("xorq %rdx, %rdx")
  asm("movq $0x1250f00, %rdi")
  asm("xorq %r8, %r8")
  asm("movq $56, %rax")
  asm("syscall")
  asm("testq %rax, %rax")
  asm("jz .Lclone_child")
  asm("ret")
  asm(".Lclone_child:")
  asm("movq %r13, %rdi")
  asm("call *%r12")
  asm("xorq %rdi, %rdi")
  asm("movq $60, %rax")
  asm("syscall")
}

## A joinable thread handle: the CHILD_CLEARTID join word address (kernel clears it to 0 and
## FUTEX_WAKEs on thread exit) plus the mapped stack region to reclaim on `join`.
pub Thread := struct { ctid_addr : usize, stack_base : usize, stack_len : usize }

## Spawn a thread that runs `fn_ptr(arg)` (a `fn(usize)` code pointer + its single word arg).
## Maps a 64 KiB stack (PROT_READ|WRITE=3, MAP_PRIVATE|ANON=0x22=34), ARMS the join word to 1
## at the region base BEFORE the clone (CRITICAL: closes the race where the parent reads the
## word as 0 before CHILD_SETTID runs), then clones. Returns the `Thread` handle (the raw child
## tid is discarded — the join word is the join primitive).
pub spawn := fn(fn_ptr : usize, arg : usize) -> Thread when target.arch == Arch.x86_64 {
  slen := 65536
  neg1 : isize = 0 - 1
  base := unchecked sys_mmap(9, 0, slen, 3, 34, bitcast(usize, neg1), 0)
  ubase := unchecked bitcast(usize, base)
  top := ubase + slen
  cp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), ubase)
  deref(cp) = 1
  tid := spawn_raw(fn_ptr, arg, top, ubase)
  return Thread(ctid_addr = ubase, stack_base = ubase, stack_len = slen)
}

## Wait for `t` to finish, then reclaim its stack. Loops: read the join word; when it is 0 the
## thread has exited (kernel cleared CHILD_CLEARTID); otherwise `futex(&word, FUTEX_WAIT=0,
## expected=current, NULL)` sleeps until the kernel FUTEX_WAKEs on thread exit (a stale/changed
## word makes the wait return EAGAIN and we re-check — no lost-wakeup). Then munmap the stack.
pub join := fn(in t : Thread) when target.arch == Arch.x86_64 {
  mut done := false
  while done == false {
    cp : ptr(u64) = unchecked bitcast(ptr(u64), t.ctid_addr)
    cur := deref(cp)
    if cur == 0 {
      done = true
    } else {
      fr := unchecked sys_futex(202, t.ctid_addr, 0, cur, 0, 0, 0)
    }
  }
  mr := unchecked sys_munmap(11, t.stack_base, t.stack_len)
}
