## std::sysno — the Linux system-call numbers the library passes to its `@abi(syscall)` declarations,
## one row per call and target architecture.
##
## ABI §5: a syscall number is "OS-version data the programmer supplies, not fixed here". So it is
## library data, chosen per target by a `when` guard (Comptime §7.1), never a constant a backend maps
## (owner decision D3, #786). Every architecture the compiler targets runs Linux, so each row is
## guarded on the architecture alone. x86_64 has its own table; aarch64 and riscv64 share the kernel's
## generic one (`include/uapi/asm-generic/unistd.h`).
##
## A call that the generic table does not have (`open`, `fork`: the generic kernel has only `openat`
## and `clone`) has an x86_64 row only. On aarch64 and riscv64 its name resolves to nothing, so a
## program that reaches it fails loudly instead of issuing whatever call the x86_64 number names there.
pub READ : usize = 0 when target.arch == Arch.x86_64
pub READ : usize = 63 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub WRITE : usize = 1 when target.arch == Arch.x86_64
pub WRITE : usize = 64 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub OPEN : usize = 2 when target.arch == Arch.x86_64
pub CLOSE : usize = 3 when target.arch == Arch.x86_64
pub CLOSE : usize = 57 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub LSEEK : usize = 8 when target.arch == Arch.x86_64
pub LSEEK : usize = 62 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub MMAP : usize = 9 when target.arch == Arch.x86_64
pub MMAP : usize = 222 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub MUNMAP : usize = 11 when target.arch == Arch.x86_64
pub MUNMAP : usize = 215 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub SCHED_YIELD : usize = 24 when target.arch == Arch.x86_64
pub SCHED_YIELD : usize = 124 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub FORK : usize = 57 when target.arch == Arch.x86_64
pub EXECVE : usize = 59 when target.arch == Arch.x86_64
pub EXECVE : usize = 221 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub WAIT4 : usize = 61 when target.arch == Arch.x86_64
pub WAIT4 : usize = 260 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub FUTEX : usize = 202 when target.arch == Arch.x86_64
pub FUTEX : usize = 98 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
pub CLOCK_GETTIME : usize = 228 when target.arch == Arch.x86_64
pub CLOCK_GETTIME : usize = 113 when target.arch == Arch.aarch64 or target.arch == Arch.riscv64
