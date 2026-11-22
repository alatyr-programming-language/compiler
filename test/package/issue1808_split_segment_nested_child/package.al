## Issue #1808 — a module's child is a whole path segment, never one that a path separator splits, below
## the root as at it. `src/m/b__c.al` is the module `m::b__c`, and `src/m/b/c/k.al` is the module
## `m::b::c::k`, identity `m__b__c__k` (Modules §1, §6.6). After `m` and its separator the text reads
## `b__c` with a separator after it, but the `__` inside is a separator too: it runs through `m::b::c`, not
## through `m::b__c`. Written in `m::r`, `b__c::k::C` climbs `m::r` -> `m`, whose child `b__c` is the file
## `src/m/b__c.al` (Modules §5); its `k := z` binds `k` to the module `z` (Modules §4.1), so `C` is `z`'s
## `pub C := u64` (Declarations §5, §6.1). `rd(b__c::k::C, h)` reads all eight bytes of 10759 and divides
## by 256: 42. Matching the child segment's text without asking whether a separator falls inside it took
## `m::b::c::k`'s `pub C := u8`, registered `rd` at `u8`, and answered 0.
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
      output = "issue1808-split-segment-nested-child",
    ),
  ],
)
## spec: Modules §1, §3, §4.1, §5, §6.6; Declarations §5, §6.1; Comptime §3.2
## expect: run 42
