## Modules §3 — the AMBIGUITY reject for a bare ENUM name. `enum_decl_of` is a SEPARATE resolver from
## `struct_decl_of` (and a raw `union` parses to the same kind-3 declaration, so this covers unions
## too), which is why the enum case needs its own fixture rather than riding the struct one.
##
## `user` names `E` bare; `aone` and `atwo` both declare an `E`, neither is `pub`, and `user` is
## nested in neither — §3 lets it name neither, and no projection, alias or qualified path in `user`
## says which it means. Measured on the frozen seed before TYPE-ANCESTOR: this BUILT and returned
## 58, having silently sized `atwo`s 32-byte `E`.
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
      output = "module-type-enum-ambiguous-reject",
    ),
  ],
)
