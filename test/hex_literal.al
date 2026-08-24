## e2e (hexadecimal integer literals `0x…`). The lexer's number tokenizer consumed only decimal
## digits, so `0xFF` split into `0` + the ident `xFF`, and `dec_val` was decimal-only — a hex literal
## silently evaluated to 0. Now the lexer scans `0x`/`0X` + hex digits as one integer token and
## `dec_val` decodes it. Exercises hex values, hex in bitwise ops, and hex mixed with decimal.
main := fn() -> u64 {
  a : u64 = 0x2A          ## 42
  b : u64 = 0xFF          ## 255
  c : u64 = 0x100         ## 256
  d : u64 = 0xABCD        ## 43981
  ## a=42; (b & 0x0F)=15; (b | c)=511; (d & 0xFF)=0xCD=205
  ## 42 + 15 + 511 + 205 = 773; want 42 -> 42 + (15-15) + (511-511) + (205-205)
  a + ((b & 0x0F) - 0xF) + ((b | c) - 511) + ((d & 0xFF) - 0xCD)
}
