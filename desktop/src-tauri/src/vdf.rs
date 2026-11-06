use std::collections::BTreeMap;
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Text(String),
    Object(BTreeMap<String, Value>),
}
pub type Object = BTreeMap<String, Value>;
pub fn text<'a>(value: &'a Object, key: &str) -> Option<&'a str> {
    if let Some(Value::Text(s)) = value.get(key) {
        Some(s)
    } else {
        None
    }
}
pub fn object<'a>(value: &'a Object, key: &str) -> Option<&'a Object> {
    if let Some(Value::Object(s)) = value.get(key) {
        Some(s)
    } else {
        None
    }
}
pub fn parse(input: &str) -> Result<Object, String> {
    struct Parser {
        chars: Vec<char>,
        i: usize,
    }
    impl Parser {
        fn space(&mut self) {
            loop {
                while self.i < self.chars.len() && self.chars[self.i].is_whitespace() {
                    self.i += 1
                }
                if self.chars.get(self.i) == Some(&'/') && self.chars.get(self.i + 1) == Some(&'/')
                {
                    while self.i < self.chars.len() && self.chars[self.i] != '\n' {
                        self.i += 1
                    }
                } else {
                    break;
                }
            }
        }
        fn token(&mut self) -> Result<String, String> {
            self.space();
            if self.chars.get(self.i) != Some(&'"') {
                return Err(format!("Invalid VDF token at {}", self.i));
            }
            self.i += 1;
            let mut s = String::new();
            while self.i < self.chars.len() {
                let c = self.chars[self.i];
                self.i += 1;
                if c == '"' {
                    return Ok(s);
                }
                if c == '\\' && matches!(self.chars.get(self.i), Some('"' | '\\')) {
                    s.push(self.chars[self.i]);
                    self.i += 1
                } else {
                    s.push(c)
                }
            }
            Err("Unterminated VDF string".into())
        }
        fn obj(&mut self, nested: bool) -> Result<Object, String> {
            let mut map = Object::new();
            loop {
                self.space();
                if self.i == self.chars.len() {
                    return if nested {
                        Err("Unterminated VDF object".into())
                    } else {
                        Ok(map)
                    };
                }
                if self.chars[self.i] == '}' {
                    if !nested {
                        return Err("Unexpected closing brace".into());
                    }
                    self.i += 1;
                    return Ok(map);
                }
                let key = self.token()?;
                self.space();
                let value = if self.chars.get(self.i) == Some(&'{') {
                    self.i += 1;
                    Value::Object(self.obj(true)?)
                } else {
                    Value::Text(self.token()?)
                };
                map.insert(key, value);
            }
        }
    }
    Parser {
        chars: input.trim_start_matches('\u{feff}').chars().collect(),
        i: 0,
    }
    .obj(false)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_and_escaped() {
        let x = parse(
            r#"// c
"root" { "path" "C:\\Steam" "n" "4" }"#,
        )
        .unwrap();
        assert_eq!(text(object(&x, "root").unwrap(), "path"), Some("C:\\Steam"));
        assert!(parse("\"root\" {").is_err());
        assert!(parse("}").is_err());
    }
}
