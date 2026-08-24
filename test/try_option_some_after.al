half := fn(x:u64)->Option(u64){ if x>0 { return Option.Some(x) } return Option.None }

use := fn(x:u64)->Option(u64){ v := half(x)?; return Option.Some(v + 1) }

main := fn()->u64{
  match use(41) {
    Option::Some(v) => { return v }
    Option::None => { return 200 }
  }
}
