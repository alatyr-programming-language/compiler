## The library's tests (Tooling §4.1): `alatyr test` in this directory.

@test("parses a scalar") fn() {
  r := std::os::arena(65536)
  match r {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      match text::parse(ptr(mut ar), "42") {
        Ok(v) => {
          match v {
            value::Value.Int(n) => {
              if n != 42 { panic("value") }
            }
            _ => {
              panic("variant")
            }
          }
        }
        Err(_) => {
          panic("parse")
        }
      }
      std::os::free(osa)
    }
    Err(_) => {
      panic("arena")
    }
  }
}
