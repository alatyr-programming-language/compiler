## e2e — Comptime §4/§9.1: the closed comptime facts a `comptime if` condition may be, all of which
## used to fall through to "cannot fold" and therefore emitted NEITHER branch (a silent deletion of
## both arms). Each now folds through the SAME `when`-guard helpers the declaration guards use.
K := true
J := false
S := struct { a : u64, b : u64, c : u64 }
main := fn() -> u64 {
  mut x : u64 = 0
  comptime if K { x = x + 1 } else { x = x + 100 }            ## a module const bool
  comptime if J { x = x + 100 } else { x = x + 2 }            ## …and its negation
  comptime if 1 < 2 { x = x + 4 } else { x = x + 100 }        ## a literal comparison
  comptime if 7 >= 9 { x = x + 100 } else { x = x + 8 }
  comptime if size(u64) == 8 { x = x + 16 } else { x = x + 100 }        ## §8 word model
  comptime if size(S) == 24 { x = x + 32 } else { x = x + 100 }
  comptime if u64 == u64 { x = x + 64 } else { x = x + 100 }            ## §4.1 type equality
  comptime if u32 == u64 { x = x + 100 } else { x = x + 128 }
  comptime if typeinfo(S).fields.len == 3 { x = x + 256 } else { x = x + 100 }
  comptime if (match typeinfo(S) { Struct(_) => true; _ => false }) { x = x + 512 } else { x = x + 100 }
  ## all ten taken correctly ⇒ x == 1023 (one distinct bit each), so the result is 42; any wrong
  ## branch shifts x by ≥ 98 and the answer is unmistakably not 42.
  return x - 981
}
