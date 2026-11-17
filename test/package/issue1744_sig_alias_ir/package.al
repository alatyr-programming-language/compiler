## Issue #1744, review of PR #1748 (B2): a callee from another module whose signature spells a name
## declared once (`T`), which is an alias of a name declared in both modules (`Inner`). The IR builder
## lays a callee's signature types out from the caller's module (#1734), so it must follow `T` to
## `Inner` and refuse the call, not lay `m::mk`'s result out as the root's three-word `Inner`.
## NON-VACUOUS: on the PR's first head 0f90e2a9 `main::use` was built from the IR, and x86_64 answered
## a value that changed from run to run.
## Expected exit 42: the two fields of `m::mk`'s result, 20 and 22.
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
      output = "issue1744-sig-alias-ir",
    ),
  ],
)
## expect: run 42
