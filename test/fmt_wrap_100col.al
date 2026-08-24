## e2e/fmt — §4.2.3, the 100-column rule. fmt did NO wrapping at all: a call's argument list, an
## array literal, a struct constructor's fields and a parameter list came out on ONE line however
## wide, so `alatyr fmt` was not conforming — and by TOOL-2 the canonical form is NORMATIVE
## (byte-identical across conforming implementations), which makes a line fmt refuses to fold a
## DIVERGENCE, not a preference. Nothing in the corpus arbiter can see it: line width never changes
## what a program does, which is exactly why it survived this long.
##
## Every over-long construct below must come back with each element on its own line, indented ONE
## level beyond the opening line, with a TRAILING COMMA after the last element and the closing
## bracket back at the opening line's indent. The short forms beside them must stay on one line and
## must NOT gain a trailing comma — "a construct that fits at its indent is written on one line".
## The `fmt-has` needles are the assertion; the exit status only proves the wrap is semantics-
## preserving (a re-parse of the wrapped text must rebuild the same tree, trailing comma included).
Wide := struct { alpha : u64, beta : u64, gamma : u64, delta : u64, epsilon : u64 }

## A parameter list wide enough to overflow: five parameters plus the name and the result type.
widest := fn(alpha_value : u64, beta_value : u64, gamma_value : u64, delta_value : u64, epsilon_value : u64) -> u64 {
  alpha_value + beta_value + gamma_value + delta_value + epsilon_value
}

## Fits at its indent — must come back untouched, and with no trailing comma.
narrow := fn(a : u64, b : u64) -> u64 {
  a + b
}

main := fn() -> u64 {
  wide_struct_value := Wide(alpha = 100000, beta = 200000, gamma = 300000, delta = 400000, epsilon = 500000)
  small_struct_value := Wide(alpha = 1, beta = 2, gamma = 3, delta = 4, epsilon = 5)
  wide_array_value := [1000000000, 2000000000, 3000000000, 4000000000, 5000000000, 6000000000, 700000000]
  small_array_value := [1, 2, 3]
  wide_call_computed_value := widest(1111111111, 2222222222, 3333333333, 4444444444, 555555555555555555)
  small_call_value := narrow(1, 2)
  if wide_struct_value.alpha != 100000 { return 1 }
  if small_struct_value.epsilon != 5 { return 2 }
  if wide_array_value[6] != 700000000 { return 3 }
  if small_array_value[1] != 2 { return 4 }
  if wide_call_computed_value != 555555566666666665 { return 5 }
  if small_call_value != 3 { return 6 }
  42
}
