//! A game's desktop entry, and its box art turned into Home's icon and
//! brand colour.

use std::path::Path;

use crate::library::Game;

/// Narrower than this is Sunshine's placeholder (130x180, for an app with no
/// image) or not much better: too small to fill a tile on a 4K TV.
const MIN_ART_WIDTH: u32 = 200;

/// What the tile shows.
pub enum Icon<'a> {
    /// The app's box art, on a tile of its average colour.
    Art { path: &'a Path, brand: [u8; 3] },
    /// No usable art: Moonlight's logo.
    Fallback(&'a Path),
}

/// Box art worth showing: a PNG wide enough, and its average colour.
pub fn art_brand(png: &[u8]) -> Option<[u8; 3]> {
    let mut decoder = png::Decoder::new(png);
    decoder.set_transformations(png::Transformations::normalize_to_color8());
    let mut reader = decoder.read_info().ok()?;
    let mut pixels = vec![0; reader.output_buffer_size()];
    let frame = reader.next_frame(&mut pixels).ok()?;
    if frame.width < MIN_ART_WIDTH {
        return None;
    }
    let channels = frame.color_type.samples();
    let pixels = &pixels[..frame.buffer_size()];
    let mut sum = [0u64; 3];
    let mut count = 0u64;
    for px in pixels.chunks_exact(channels) {
        let rgb = match channels {
            1 | 2 => [px[0]; 3],
            _ => [px[0], px[1], px[2]],
        };
        for (s, c) in sum.iter_mut().zip(rgb) {
            *s += u64::from(c);
        }
        count += 1;
    }
    (count > 0).then(|| sum.map(|s| (s / count) as u8))
}

pub struct Commands<'a> {
    /// Takes `<address> <app name>`.
    pub stream: &'a Path,
    /// Takes `<address>`.
    pub quit: &'a Path,
}

pub fn render(game: &Game, commands: &Commands, icon: &Icon) -> String {
    let address = game.address.to_string();
    let stream = exec(&[&commands.stream.to_string_lossy(), &address, &game.app.name]);
    let quit = exec(&[&commands.quit.to_string_lossy(), &address]);
    let (icon_path, brand) = match icon {
        Icon::Art { path, brand } => (*path, Some(*brand)),
        Icon::Fallback(path) => (*path, None),
    };
    let mut text = format!(
        "# Written by emrakul-games from {}'s app list; rewritten on every run.\n\
         [Desktop Entry]\n\
         Type=Application\n\
         Name={}\n\
         Exec={stream}\n\
         Icon={}\n\
         X-Emrakul-Quit={quit}\n\
         X-Emrakul-Tv=game\n\
         X-Emrakul-Controller=app\n",
        game.host,
        string(&game.name),
        string(&icon_path.to_string_lossy()),
    );
    if let Some([r, g, b]) = brand {
        text.push_str(&format!("X-Emrakul-Brand=#{r:02x}{g:02x}{b:02x}\n"));
    }
    text
}

/// An Exec value: every argument quoted, then escaped as a string, which is
/// the order the spec unescapes them in reverse.
fn exec(args: &[&str]) -> String {
    let quoted: Vec<String> = args
        .iter()
        .map(|arg| {
            let mut q = String::from('"');
            for c in arg.chars() {
                if matches!(c, '"' | '`' | '$' | '\\') {
                    q.push('\\');
                }
                q.push(c);
            }
            q.push('"');
            q
        })
        .collect();
    string(&quoted.join(" "))
}

/// A string value's escapes.
fn string(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_quotes_then_escapes() {
        assert_eq!(
            exec(&["/nix/store/x/bin/s", "10.0.0.1", "V Rising"]),
            r#""/nix/store/x/bin/s" "10.0.0.1" "V Rising""#
        );
        // `a "b" $c \d` quoted is "a \"b\" \$c \\d", then each \ doubles.
        assert_eq!(exec(&[r#"a "b" $c \d"#]), r#""a \\"b\\" \\$c \\\\d""#);
    }

    #[test]
    fn art_must_be_a_png_wide_enough() {
        let png = |width, height, colour: [u8; 3]| {
            let mut out = Vec::new();
            let mut encoder = png::Encoder::new(&mut out, width, height);
            encoder.set_color(png::ColorType::Rgb);
            let mut writer = encoder.write_header().unwrap();
            let data: Vec<u8> = (0..width * height).flat_map(|_| colour).collect();
            writer.write_image_data(&data).unwrap();
            drop(writer);
            out
        };
        assert_eq!(art_brand(&png(300, 450, [10, 20, 30])), Some([10, 20, 30]));
        assert_eq!(art_brand(&png(130, 180, [10, 20, 30])), None);
        assert_eq!(art_brand(b"<html>not art</html>"), None);
    }
}
