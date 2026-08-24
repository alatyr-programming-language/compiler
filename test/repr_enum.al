## §8 @repr(T) — the tagged-enum tag-representation lever (spec Types §8). Three enums pin their
## discriminant (tag) to an explicit integer type — `@repr(i32)` (a C-ABI-width tag) and `@repr(u8)`
## (a byte tag) — overriding the §6.2 word-sized default. Each is CONSTRUCTED then MATCHED; the match
## dispatch loads the tag at T's width (movslq / movzbl) and must still select the correct arm. `Move`
## carries a payload that stays word-sized (the lever fixes ONLY the tag, not the payload), so reading
## it back proves the payload was not disturbed. A wrong tag width or a mis-selected arm returns a
## sentinel; the correct sum is 20 + 20 + 2 = 42.
Color := @repr(i32) enum { Red, Green, Blue }
State := @repr(u8) enum { Idle, Run, Stop, Done }
Msg := @repr(i32) enum { Quit, Move(u64), Write(u64) }

main := fn() -> u64 {
  mut acc := 0
  c := Color.Blue
  match c {
    Color.Red => { acc = acc + 1 }
    Color.Green => { acc = acc + 2 }
    Color.Blue => { acc = acc + 20 }
  }
  s := State.Done
  match s {
    State.Idle => { acc = acc + 1 }
    State.Run => { acc = acc + 2 }
    State.Stop => { acc = acc + 3 }
    State.Done => { acc = acc + 20 }
  }
  m := Msg.Move(2)
  match m {
    Msg.Quit => { acc = acc + 100 }
    Msg.Move(x) => { acc = acc + x }
    Msg.Write(y) => { acc = acc + y }
  }
  acc
}
