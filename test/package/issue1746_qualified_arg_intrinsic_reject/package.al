## Issue #1746 / Functions §2.2, Types §4.1, §4.3 — `main` passes a struct `S` to the qualified
## `util::len`, whose one parameter is `u64`. `len` is also an intrinsic name. No parameter accepts
## an `S`, and an aggregate never converts implicitly to a scalar, so the call is ill-formed, as the
## unqualified spelling of the same call already is. PARENT (main 637366a9), native x86_64: check 0
## and every backend ran it to a value read off the struct's bits — `alatyr run` 62, the built
## artifact 142 on IR and legacy alike, aarch64 230, riscv64 6, wasm 38. Expected: check and build
## rc 1, located at the argument, line 3 of `main`.
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
      output = "issue1746-qualified-arg-intrinsic-reject",
    ),
  ],
)
## expect: reject "type mismatch" "at line 3"
