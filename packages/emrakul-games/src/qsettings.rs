//! Reading a QSettings INI file, such as Moonlight.conf. A port of the parts
//! of Qt 6's qsettings.cpp that its own writer can produce: `[section]`
//! headers, `\`-separated array keys, `%XX` key escapes, quoted and
//! backslash-escaped values, and `@ByteArray(...)`.
//! <https://github.com/qt/qtbase/blob/6.9/src/corelib/io/qsettings.cpp>

use std::collections::BTreeMap;

/// One file's keys, `/`-separated the way QSettings names them:
/// `hosts/1/apps/2/name`. Keys in `[General]` have no prefix.
#[derive(Debug, Default)]
pub struct Settings(BTreeMap<String, Value>);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Value {
    Text(String),
    Bytes(Vec<u8>),
    List(Vec<String>),
    /// `@Invalid()`, `@Variant(...)` and the like: nothing we read.
    Other,
}

impl Settings {
    pub fn parse(text: &str) -> Self {
        let text = text.strip_prefix('\u{feff}').unwrap_or(text);
        let mut keys = BTreeMap::new();
        let mut section = String::new();
        for line in text.lines().map(str::trim) {
            if line.is_empty() || line.starts_with(';') {
                continue;
            }
            if let Some(header) = line.strip_prefix('[') {
                let name = header.split(']').next().unwrap_or(header).trim();
                section = if name.eq_ignore_ascii_case("general") {
                    String::new()
                } else {
                    unescape_key(name) + "/"
                };
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let key = format!("{section}{}", unescape_key(key.trim()));
            keys.insert(key, to_value(unescape_value(value.as_bytes())));
        }
        Self(keys)
    }

    pub fn get(&self, key: &str) -> Option<&Value> {
        self.0.get(key)
    }

    /// A string value. QSettings hands numbers and bools back as strings too.
    pub fn text(&self, key: &str) -> Option<&str> {
        match self.get(key)? {
            Value::Text(text) => Some(text),
            _ => None,
        }
    }

    pub fn bytes(&self, key: &str) -> Option<&[u8]> {
        match self.get(key)? {
            Value::Bytes(bytes) => Some(bytes),
            _ => None,
        }
    }

    /// An array's length, as `QSettings::beginReadArray` reads it.
    pub fn array_len(&self, prefix: &str) -> usize {
        self.text(&format!("{prefix}/size"))
            .and_then(|n| n.parse().ok())
            .unwrap_or(0)
    }
}

/// `stringToVariant`.
fn to_value(unescaped: Unescaped) -> Value {
    let text = match unescaped {
        Unescaped::List(items) => return Value::List(items),
        Unescaped::Single(text) => text,
    };
    if let Some(rest) = text.strip_prefix('@') {
        if let Some(inner) = rest
            .strip_prefix("ByteArray(")
            .and_then(|r| r.strip_suffix(')'))
        {
            // QString::toLatin1: every char is one byte.
            return inner
                .chars()
                .map(|c| u8::try_from(u32::from(c)).ok())
                .collect::<Option<Vec<u8>>>()
                .map_or(Value::Other, Value::Bytes);
        }
        if let Some(inner) = rest
            .strip_prefix("String(")
            .and_then(|r| r.strip_suffix(')'))
        {
            return Value::Text(inner.to_owned());
        }
        if let Some(escaped_at) = rest.strip_prefix('@') {
            return Value::Text(format!("@{escaped_at}"));
        }
        return Value::Other;
    }
    Value::Text(text)
}

/// `iniUnescapedKey`: `\` separates groups, `%XX` and `%UXXXX` are chars.
fn unescape_key(key: &str) -> String {
    let chars: Vec<char> = key.chars().collect();
    let mut out = String::with_capacity(key.len());
    let mut i = 0;
    while i < chars.len() {
        match chars[i] {
            '\\' => {
                out.push('/');
                i += 1;
            }
            '%' if i + 1 < chars.len() => {
                let (start, digits) = if chars[i + 1] == 'U' {
                    (i + 2, 4)
                } else {
                    (i + 1, 2)
                };
                let code = chars
                    .get(start..start + digits)
                    .map(|d| d.iter().collect::<String>())
                    .and_then(|d| u32::from_str_radix(&d, 16).ok())
                    .and_then(char::from_u32);
                match code {
                    Some(c) => {
                        out.push(c);
                        i = start + digits;
                    }
                    None => {
                        out.push('%');
                        i += 1;
                    }
                }
            }
            c => {
                out.push(c);
                i += 1;
            }
        }
    }
    out
}

#[derive(Debug, PartialEq, Eq)]
enum Unescaped {
    Single(String),
    /// Unquoted commas make a value a string list.
    List(Vec<String>),
}

/// `iniUnescapedStringList`, its goto states turned into a loop.
fn unescape_value(raw: &[u8]) -> Unescaped {
    let mut out = String::new();
    let mut list: Option<Vec<String>> = None;
    let mut in_quotes = false;
    let mut quoted = false;
    let mut i = 0;
    skip_spaces(raw, &mut i);
    // Trailing spaces after this point are chopped unless the value was
    // quoted; escaped ones never are.
    let mut chop_limit = 0;
    while i < raw.len() {
        match raw[i] {
            b'\\' => {
                i += 1;
                let Some(&c) = raw.get(i) else { break };
                i += 1;
                if let Some(plain) = simple_escape(c) {
                    out.push(plain);
                } else if c == b'x' {
                    if let Some(code) = digits(raw, &mut i, 16) {
                        out.push(code);
                    }
                } else if (b'0'..=b'7').contains(&c) {
                    i -= 1;
                    if let Some(code) = digits(raw, &mut i, 8) {
                        out.push(code);
                    }
                }
                // Anything else after a backslash is dropped. (Qt also
                // continues a value over an escaped line break, which its
                // writer never produces and a per-line read never sees.)
                chop_limit = out.len();
            }
            b'"' => {
                i += 1;
                quoted = true;
                in_quotes = !in_quotes;
                if !in_quotes {
                    skip_spaces(raw, &mut i);
                    chop_limit = out.len();
                }
            }
            b',' if !in_quotes => {
                if !quoted {
                    chop_trailing_spaces(&mut out, chop_limit);
                }
                list.get_or_insert_with(Vec::new)
                    .push(std::mem::take(&mut out));
                quoted = false;
                i += 1;
                skip_spaces(raw, &mut i);
                chop_limit = 0;
            }
            _ => {
                let start = i;
                i += 1;
                while i < raw.len() && !matches!(raw[i], b'\\' | b'"' | b',') {
                    i += 1;
                }
                out.push_str(&String::from_utf8_lossy(&raw[start..i]));
            }
        }
    }
    if !quoted {
        chop_trailing_spaces(&mut out, chop_limit);
    }
    match list {
        Some(mut items) => {
            items.push(out);
            Unescaped::List(items)
        }
        None => Unescaped::Single(out),
    }
}

fn simple_escape(c: u8) -> Option<char> {
    Some(match c {
        b'a' => '\x07',
        b'b' => '\x08',
        b'f' => '\x0c',
        b'n' => '\n',
        b'r' => '\r',
        b't' => '\t',
        b'v' => '\x0b',
        b'"' => '"',
        b'?' => '?',
        b'\'' => '\'',
        b'\\' => '\\',
        _ => return None,
    })
}

/// Greedy digits in `radix` from `i`, as one UTF-16 code unit the way Qt's
/// char16_t accumulator keeps it. `None` when there were no digits.
fn digits(raw: &[u8], i: &mut usize, radix: u32) -> Option<char> {
    let mut value: u32 = 0;
    let mut any = false;
    while let Some(d) = raw.get(*i).and_then(|&b| (b as char).to_digit(radix)) {
        value = (value * radix + d) & 0xffff;
        *i += 1;
        any = true;
    }
    any.then(|| char::from_u32(value).unwrap_or(char::REPLACEMENT_CHARACTER))
}

fn skip_spaces(raw: &[u8], i: &mut usize) {
    while raw.get(*i).is_some_and(|&b| b == b' ' || b == b'\t') {
        *i += 1;
    }
}

fn chop_trailing_spaces(out: &mut String, limit: usize) {
    while out.len() > limit && (out.ends_with(' ') || out.ends_with('\t')) {
        out.pop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn moonlight_conf_shapes() {
        let conf = Settings::parse(concat!(
            "[General]\n",
            "certificate=@ByteArray(-----BEGIN CERTIFICATE-----\\nMIIC\\n-----END CERTIFICATE-----\\n)\n",
            "key=\"@ByteArray(-----BEGIN PRIVATE KEY-----\\nab+/=\\n)\"\n",
            "uniqueid=40d04afe2347bc08\n",
            "\n[hosts]\n",
            "1\\apps\\1\\name=V Rising\n",
            "1\\apps\\size=1\n",
            "1\\mac=\"@ByteArray(,\\xf0]\\xcf\\x62\\x1a)\"\n",
            "1\\localport=47989\n",
            "1\\customname=false\n",
            "size=1\n",
        ));
        assert_eq!(
            conf.bytes("certificate"),
            Some(&b"-----BEGIN CERTIFICATE-----\nMIIC\n-----END CERTIFICATE-----\n"[..])
        );
        assert_eq!(
            conf.bytes("key"),
            Some(&b"-----BEGIN PRIVATE KEY-----\nab+/=\n"[..])
        );
        assert_eq!(conf.text("uniqueid"), Some("40d04afe2347bc08"));
        assert_eq!(conf.text("hosts/1/apps/1/name"), Some("V Rising"));
        assert_eq!(conf.array_len("hosts"), 1);
        assert_eq!(conf.array_len("hosts/1/apps"), 1);
        assert_eq!(
            conf.bytes("hosts/1/mac"),
            Some(&[0x2c, 0xf0, 0x5d, 0xcf, 0x62, 0x1a][..])
        );
    }

    #[test]
    fn values_unescape_like_qt() {
        let single = |raw: &str| match unescape_value(raw.as_bytes()) {
            Unescaped::Single(s) => s,
            other => panic!("{raw}: {other:?}"),
        };
        assert_eq!(single("  plain text  "), "plain text");
        assert_eq!(single("\" padded \""), " padded ");
        assert_eq!(single("a\\\"b\\\\c"), "a\"b\\c");
        assert_eq!(single("\"x;y=z\""), "x;y=z");
        assert_eq!(single("tab\\t "), "tab\t");
        assert_eq!(single("\\0"), "\0");
        assert_eq!(single("caf\u{e9}"), "caf\u{e9}");
        assert_eq!(single("\\x41\\x42"), "AB");
        assert_eq!(
            unescape_value(b"a, b ,\"c, d\""),
            Unescaped::List(vec!["a".into(), "b".into(), "c, d".into()])
        );
    }

    #[test]
    fn keys_unescape_like_qt() {
        assert_eq!(unescape_key("1\\apps\\size"), "1/apps/size");
        assert_eq!(unescape_key("a%3Db%U00e9"), "a=b\u{e9}");
        assert_eq!(unescape_key("100%"), "100%");
    }

    #[test]
    fn at_prefixes() {
        assert_eq!(
            to_value(Unescaped::Single("@@at".into())),
            Value::Text("@at".into())
        );
        assert_eq!(
            to_value(Unescaped::Single("@Invalid()".into())),
            Value::Other
        );
        assert_eq!(
            to_value(Unescaped::Single("@String(x)".into())),
            Value::Text("x".into())
        );
    }
}
