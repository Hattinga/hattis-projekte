//! Tiny built-in 5×7 bitmap font.
//!
//! Used for the frame counter burned into the synthetic test pattern and for
//! the statistics overlay. It avoids pulling in a font rasterizer crate for a
//! handful of uppercase status lines. Lowercase input is rendered uppercase;
//! characters without a glyph render as `?`.

/// Glyph width in cells.
pub const GLYPH_WIDTH: usize = 5;
/// Glyph height in cells.
pub const GLYPH_HEIGHT: usize = 7;
/// Horizontal distance between the starts of two consecutive glyphs.
pub const ADVANCE: usize = GLYPH_WIDTH + 1;

type Glyph = [&'static str; GLYPH_HEIGHT];

const UNKNOWN: Glyph = [
    " ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  ",
];

#[rustfmt::skip]
const GLYPHS: &[(char, Glyph)] = &[
    (' ', ["     ", "     ", "     ", "     ", "     ", "     ", "     "]),
    ('0', [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "]),
    ('1', ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "]),
    ('2', [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"]),
    ('3', ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "]),
    ('4', ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "]),
    ('5', ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "]),
    ('6', ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "]),
    ('7', ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "]),
    ('8', [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "]),
    ('9', [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "]),
    ('A', [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"]),
    ('B', ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "]),
    ('C', [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "]),
    ('D', ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "]),
    ('E', ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"]),
    ('F', ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "]),
    ('G', [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"]),
    ('H', ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"]),
    ('I', [" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "]),
    ('J', ["  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "]),
    ('K', ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"]),
    ('L', ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"]),
    ('M', ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"]),
    ('N', ["#   #", "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #"]),
    ('O', [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "]),
    ('P', ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "]),
    ('Q', [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"]),
    ('R', ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"]),
    ('S', [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "]),
    ('T', ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "]),
    ('U', ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "]),
    ('V', ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "]),
    ('W', ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", " # # "]),
    ('X', ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"]),
    ('Y', ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "]),
    ('Z', ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"]),
    ('.', ["     ", "     ", "     ", "     ", "     ", " ##  ", " ##  "]),
    (',', ["     ", "     ", "     ", "     ", " ##  ", "  #  ", " #   "]),
    (':', ["     ", " ##  ", " ##  ", "     ", " ##  ", " ##  ", "     "]),
    ('/', ["     ", "    #", "   # ", "  #  ", " #   ", "#    ", "     "]),
    ('-', ["     ", "     ", "     ", "#####", "     ", "     ", "     "]),
    ('+', ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "]),
    ('=', ["     ", "     ", "#####", "     ", "#####", "     ", "     "]),
    ('>', [" #   ", "  #  ", "   # ", "    #", "   # ", "  #  ", " #   "]),
    ('<', ["   # ", "  #  ", " #   ", "#    ", " #   ", "  #  ", "   # "]),
    ('(', ["   # ", "  #  ", " #   ", " #   ", " #   ", "  #  ", "   # "]),
    (')', [" #   ", "  #  ", "   # ", "   # ", "   # ", "  #  ", " #   "]),
    ('%', ["##   ", "##  #", "   # ", "  #  ", " #   ", "#  ##", "   ##"]),
    ('_', ["     ", "     ", "     ", "     ", "     ", "     ", "#####"]),
    ('|', ["  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "]),
    ('@', [" ### ", "#   #", "# ###", "# # #", "# ###", "#    ", " ### "]),
    ('?', UNKNOWN),
];

fn glyph(c: char) -> &'static Glyph {
    let c = c.to_ascii_uppercase();
    GLYPHS
        .iter()
        .find(|(gc, _)| *gc == c)
        .map_or(&UNKNOWN, |(_, g)| g)
}

/// Width in cells of `text` rendered on one line (no trailing spacing).
pub fn text_width(text: &str) -> usize {
    match text.chars().count() {
        0 => 0,
        n => n * ADVANCE - 1,
    }
}

/// Calls `plot(x, y)` for every lit cell of `text`, with `(0, 0)` at the top
/// left of the first glyph. Callers scale cells to pixels.
pub fn rasterize(text: &str, mut plot: impl FnMut(usize, usize)) {
    for (index, c) in text.chars().enumerate() {
        let origin = index * ADVANCE;
        for (y, row) in glyph(c).iter().enumerate() {
            for (x, cell) in row.bytes().enumerate() {
                if cell == b'#' {
                    plot(origin + x, y);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_glyph_is_5x7_and_uses_only_hash_and_space() {
        for (c, g) in GLYPHS {
            for row in g {
                assert_eq!(row.len(), GLYPH_WIDTH, "glyph {c:?} row {row:?}");
                assert!(row.bytes().all(|b| b == b'#' || b == b' '), "glyph {c:?}");
            }
        }
    }

    #[test]
    fn glyph_table_has_no_duplicates() {
        for (i, (a, _)) in GLYPHS.iter().enumerate() {
            assert!(
                GLYPHS[i + 1..].iter().all(|(b, _)| a != b),
                "duplicate {a:?}"
            );
        }
    }

    #[test]
    fn lowercase_maps_to_uppercase_and_unknown_to_question_mark() {
        assert_eq!(glyph('a'), glyph('A'));
        assert_eq!(glyph('ä'), &UNKNOWN);
    }

    #[test]
    fn rasterize_stays_within_text_width() {
        let text = "FRAME 0123456789";
        let width = text_width(text);
        let mut max_x = 0;
        let mut max_y = 0;
        rasterize(text, |x, y| {
            max_x = max_x.max(x);
            max_y = max_y.max(y);
        });
        assert!(max_x < width);
        assert!(max_y < GLYPH_HEIGHT);
        assert_eq!(text_width(""), 0);
    }
}
