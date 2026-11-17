## Issue #1753 / Functions §1.4 (FN-7), Modules §2 (MOD-3), §3, §5 — the shape of
## `issue1753_method_recv_reject` in a program that also uses `alloc::vec`, so the library's generic
## `get(T : type, v : ptr(Vec(T)), i : usize)` is in the program too. A same-named generic the root
## does not declare must not make the root's call generic and leave its argument unchecked. PARENT
## (#1755 head e43bebee), native x86_64: check 0, then x86_64 IR and legacy die by SIGSEGV (139) on
## every run, aarch64 and riscv64 trap 133, wasm traps 134. Expected: check and build rc 1, located
## at the call, line 6 of `main`.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      kind = Kind.executable,
      output = "issue1753-method-recv-reject-libgen",
    ),
  ],
)
## expect: reject "type mismatch" "at line 6"
