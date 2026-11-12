- **The shared IR builds `in out` and `out` struct and enum parameters (#1026).** Such a parameter is
  bound to the caller's place by reference (Functions §2.1, §4.1), and a call passes that place's
  address, never a copy (§2.3). Before, the builder refused every function with one and every call to
  one, so aarch64, riscv64 and wasm fell back to their legacy emitters and trapped. A whole `p = v`
  into such a parameter, scalar `in out`/`out`, array and slice-variadic parameters stay refused.
