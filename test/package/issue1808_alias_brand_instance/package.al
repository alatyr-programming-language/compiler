## Issue #1808 — an alias names the type it is bound to, and a brand is its own type. Two modules each
## declare `Node` (different field orders), an alias `A := Node` and a brand `Id := brand(Node)`, and the
## generic `second` of `m` is instantiated at each. `main::A` is the root's `Node` and `m::A` is `m`'s
## (Declarations §1.3: a declaration binds its name to its right-hand side's value), so they are two
## instances, and `A` shares `Node`'s instance (Comptime §3.2, §3.4). The two brands are two nominal
## types (Types §4.1, §5.4), so two instances too. Before the fix every alias and every brand collapsed
## into one instance by its text (`m__second__A`, `m__second__Id`), and the root's struct was read with
## `m`'s layout (x86_64 answered 14 where the program says 42). Two scalar aliases `W := u8` and
## `W := u64` are two instances as well, each reading its own width (the parent trapped on `- 256`).
## A qualified `m::A` names `m`'s alias even though the root declares its own `A` (the parent read the
## root's).
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
      output = "issue1808-alias-brand-instance",
    ),
  ],
)
## spec: Comptime §3.2, §3.4; Declarations §1.3; Types §4.1, §5.4
## expect: run 42
