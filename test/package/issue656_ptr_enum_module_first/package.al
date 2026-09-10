## Issue #656 / Control Flow §5.1 + Modules §1 — a POINTER annotation's pointee identity must not
## depend on the ORDER in which a package's modules are checked. #557 settled this for a direct
## annotation (`c : C`); the spelling every backend's `Expr` walk actually writes is `ptr(C)`, and
## that one still resolved its pointee under the name-resolution prefix. Module membership is a set,
## not a sequence, so the same program must get the same verdict whichever file name the enum's
## module happens to sort under.
## The enum's module sorts BEFORE the consuming module — the order that was already refused.
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
      output = "issue656-ptr-enum-module-first",
    ),
  ],
)
