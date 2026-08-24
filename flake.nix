{
  description = "Alatyr — the self-hosted compiler (canonical, written in Alatyr)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        # The self-host build needs only an assembler + linker: the committed static seed
        # (`seed/alatyr`) compiles the tree to GAS and drives `as`/`ld` itself. No Rust toolchain —
        # the compiler is pure Alatyr. Its Rust ancestor is frozen and not published; `seed/VERSION`
        # records the lineage.
        # `wabt` (wat2wasm) + `wasmtime` gate the WASM→WAT backend: the emitted `.wat` is
        # assembled by `wat2wasm` (structural + type validation) and run by `wasmtime` (the exit code
        # is checked like the x86_64 e2e). Without them a WASM backend can be emitted but not verified.
        # The aarch64 and riscv64 backends: a cross assembler+linker
        # (`aarch64-unknown-linux-gnu-{as,ld}`, from the cross buildPackages' binutils) assembles the
        # emitted GAS, and `qemu-aarch64` (user-mode emulation) runs the resulting static ELF so its
        # exit code can be checked exactly like the native x86_64 / wasmtime e2e paths.
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            binutils gdb wabt wasmtime qemu-user
            # DECLARED, not borrowed from the host. The idiom gate runs real awk programs
            # (`scripts/idiom/*.awk`, 12 call sites) that rely on GNU extensions; where `awk` is mawk
            # or busybox they would compute something else rather than fail, and a gate that quietly
            # measures the wrong thing is the failure this project spends the most effort avoiding.
            # `sed`, `xargs`, `timeout` and `sha256sum` come from stdenv.
            gawk
            bc                                           # scripts/incr_probe.sh's timing arithmetic
            hyperfine                                    # reproducible timing when probing by hand
            linuxPackages_latest.perf valgrind           # profilers (perf sampling / callgrind)
            # The cross-language comparison toolchains (rustc/zig/go/php/ruby/nodejs/python3) are NOT
            # here: they existed only for the benchmark harness, which is now its own repository with
            # its own flake — https://github.com/alatyr-programming-language/benchmarks
            pkgsCross.aarch64-multiplatform.buildPackages.binutils
            pkgsCross.riscv64.buildPackages.binutils
          ];
        };
      });
}
