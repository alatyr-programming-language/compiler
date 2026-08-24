## Multi-file located diagnostic (§1 item 6): checked with mf_helper.al, whose 8 lines precede
## this module in the concatenated buffer. The unbound reference is on line 5 of THIS file; the
## diagnostic must report "at line 5 in reject_located_multi", not a whole-buffer count (~13).
main := fn() -> u64 {
  return oops_undefined_name
}
