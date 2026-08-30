/// First-strong paragraph direction, per UAX #9 rules P2 and P3.
///
/// This exists because neither the previous hand-rolled regex nor `intl`'s
/// `Bidi` resolves first-strong correctly, and they fail on *different* inputs:
///
/// | input                        | old regex | `Bidi.startsWithRtl` | correct |
/// |------------------------------|-----------|----------------------|---------|
/// | `۱۲۳ hello` (U+06Fx, class EN) | rtl     | rtl                  | **ltr** |
/// | `١٢٣ hello` (U+066x, class AN) | rtl     | rtl                  | **ltr** |
/// | `ﻲ` Presentation Forms-B (AL)  | *null*  | rtl                  | **rtl** |
/// | `ﭐ` Presentation Forms-A (AL)  | *null*  | rtl                  | **rtl** |
/// | `ࠀ` Samaritan (R)              | rtl     | *ltr*                | **rtl** |
/// | `ࢠ` Arabic Extended-A (AL)     | rtl     | *ltr*                | **rtl** |
///
/// `intl`'s own source comments say its patterns "are not completely correct
/// according to the Unicode standard. They are simplified for performance and
/// small code size": its `_RTL_CHARS` is `֑-߿`, which swallows both
/// Arabic-Indic and Persian digits, while its `_LTR_CHARS` claims
/// `ࠀ-῿`, which hands Samaritan, Mandaic, Syriac Supplement and
/// Arabic Extended-A to the wrong direction. `Bidi.detectRtlDirectionality` is
/// not first-strong at all — it counts whitespace-delimited tokens against a
/// 0.40 threshold, with a special case for `^http://` that a `https://` URL
/// does not meet.
///
/// The ranges below are the strong classes from `DerivedBidiClass`: R and AL
/// for [_rtlStrong], L for [_ltrStrong]. Weak (EN, AN, ES, ET, CS), neutral
/// (WS, ON, B, S), mark (NSM) and format (BN, and the embedding controls)
/// characters appear in neither list and are skipped, which is what P2
/// requires. The RTL set is checked first, so a combining mark inside an RTL
/// block falls through both lists rather than being claimed by the broader
/// LTR ranges.
///
/// Coverage is every RTL script in the BMP plus both Arabic Presentation Form
/// blocks and the supplementary RTL planes, and, for LTR, Latin, Greek,
/// Cyrillic, Armenian, the Indic and South-East Asian blocks, CJK, Kana and
/// Hangul. A script outside those returns null rather than a guess.
library;

import 'package:flutter/painting.dart' show TextDirection;

const int _lri = 0x2066;
const int _rli = 0x2067;
const int _fsi = 0x2068;
const int _pdi = 0x2069;

/// Resolves the base direction of [text] from its first strong character.
///
/// Returns null when [text] is null, empty, or carries no strong character at
/// all — a bare number, an emoji, a URL with no letters. P3 would make that
/// case LTR; returning null instead leaves the widget inheriting the ambient
/// [Directionality], so `"۱۲۳"` on its own stays in the reading direction of
/// the surrounding conversation instead of being forced to English order. That
/// is the one deliberate departure from P3 here, and it is also what the code
/// this replaces did.
TextDirection? resolveFirstStrongDirection(String? text) {
  if (text == null || text.isEmpty) {
    return null;
  }
  // P2 skips everything between an isolate initiator and its matching PDI.
  var isolateDepth = 0;
  for (final rune in text.runes) {
    if (rune == _lri || rune == _rli || rune == _fsi) {
      isolateDepth++;
      continue;
    }
    if (rune == _pdi) {
      if (isolateDepth > 0) {
        isolateDepth--;
      }
      continue;
    }
    if (isolateDepth > 0) {
      continue;
    }
    if (_contains(_rtlStrong, rune)) {
      return TextDirection.rtl;
    }
    if (_contains(_ltrStrong, rune)) {
      return TextDirection.ltr;
    }
  }
  return null;
}

/// Binary search over a flat, ascending, non-overlapping `[lo, hi, lo, hi...]`
/// range table.
bool _contains(List<int> ranges, int rune) {
  var low = 0;
  var high = (ranges.length ~/ 2) - 1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (rune < ranges[mid * 2]) {
      high = mid - 1;
    } else if (rune > ranges[mid * 2 + 1]) {
      low = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Bidi classes R and AL.
///
/// The gaps are load-bearing. U+0660–U+0669 (AN) sits between the Arabic
/// letters ending at U+064A and those resuming at U+066D, and U+06F0–U+06F9
/// (EN) sits between U+06EF and U+06FA: the Arabic-Indic and Persian digits
/// are skipped because they are not strong, which is the defect this whole
/// file exists to fix. U+0600–U+0605 (AN), U+0610–U+061A, U+064B–U+065F,
/// U+0670 and U+06D6–U+06ED (NSM) are excluded on the same rule.
const _rtlStrong = <int>[
  0x05BE, 0x05BE, // HEBREW PUNCTUATION MAQAF
  0x05C0, 0x05C0, // HEBREW PUNCTUATION PASEQ
  0x05C3, 0x05C3, // HEBREW PUNCTUATION SOF PASUQ
  0x05C6, 0x05C6, // HEBREW PUNCTUATION NUN HAFUKHA
  0x05D0, 0x05EA, // Hebrew letters
  0x05EF, 0x05F4, // Hebrew ligatures and punctuation
  0x0608, 0x0608, // ARABIC RAY
  0x060B, 0x060B, // AFGHANI SIGN
  0x060D, 0x060D, // ARABIC DATE SEPARATOR
  0x061B, 0x064A, // Arabic punctuation and letters, incl. U+061C ALM
  0x066D, 0x066F, // ARABIC FIVE POINTED STAR .. DOTLESS QAF
  0x0671, 0x06D5, // Arabic letters
  0x06E5, 0x06E6, // ARABIC SMALL WAW, SMALL YEH
  0x06EE, 0x06EF, // ARABIC DAL, REH WITH INVERTED V
  0x06FA, 0x070D, // Arabic letters and Syriac punctuation
  0x0710, 0x0710, // SYRIAC LETTER ALAPH
  0x0712, 0x072F, // Syriac letters
  0x074D, 0x07A5, // Syriac ext., Arabic Supplement, Thaana letters
  0x07B1, 0x07B1, // THAANA LETTER NAA
  0x07C0, 0x07EA, // NKo, whose digits are class R rather than EN
  0x07F4, 0x07F5, // NKo tone apostrophes
  0x07FA, 0x07FA, // NKO LAJANYALAN
  0x07FE, 0x0815, // NKo currency signs, Samaritan letters
  0x081A, 0x081A, // SAMARITAN MODIFIER LETTER EPENTHETIC YUT
  0x0824, 0x0824, // SAMARITAN MODIFIER LETTER SHORT A
  0x0828, 0x0828, // SAMARITAN MODIFIER LETTER I
  0x0830, 0x083E, // Samaritan punctuation
  0x0840, 0x0858, // Mandaic letters
  0x085E, 0x085E, // MANDAIC PUNCTUATION
  0x0860, 0x086A, // Syriac Supplement
  0x0870, 0x088E, // Arabic Extended-B
  0x08A0, 0x08C9, // Arabic Extended-A letters
  0x200F, 0x200F, // RIGHT-TO-LEFT MARK
  0xFB1D, 0xFB1D, // HEBREW LETTER YOD WITH HIRIQ
  0xFB1F, 0xFB28, // Hebrew presentation forms
  0xFB2A, 0xFB4F, // Hebrew presentation forms
  0xFB50, 0xFD3D, // Arabic Presentation Forms-A
  0xFD40, 0xFDFF, // Arabic Presentation Forms-A, past the ornate parentheses
  0xFE70, 0xFEFC, // Arabic Presentation Forms-B
  0x10800, 0x10CFF, // Cypriot .. Old Hungarian
  0x10D00, 0x10D3F, // Hanifi Rohingya
  0x10D40, 0x10D8F, // Garay
  0x10E80, 0x10FFF, // Yezidi .. Old Uyghur, past the Rumi digits at U+10E60
  0x1E800, 0x1E8DF, // Mende Kikakui
  0x1E900, 0x1E95F, // Adlam
  0x1EC70, 0x1ECBF, // Indic Siyaq Numbers
  0x1ED00, 0x1ED4F, // Ottoman Siyaq Numbers
  0x1EE00, 0x1EEFF, // Arabic Mathematical Alphabetic Symbols
];

/// Bidi class L.
///
/// Deliberately broad, and deliberately free of every range in [_rtlStrong].
/// U+0030–U+0039 and the other digit blocks are absent, so `"123 سلام"`
/// resolves RTL on the Persian rather than LTR on the digits.
const _ltrStrong = <int>[
  0x0041, 0x005A, // A-Z
  0x0061, 0x007A, // a-z
  0x00AA, 0x00AA, // FEMININE ORDINAL INDICATOR
  0x00B5, 0x00B5, // MICRO SIGN
  0x00BA, 0x00BA, // MASCULINE ORDINAL INDICATOR
  0x00C0, 0x00D6, // Latin-1 letters
  0x00D8, 0x00F6, // Latin-1 letters
  0x00F8, 0x02B8, // Latin Extended, IPA, spacing modifiers
  0x0370, 0x0482, // Greek, Coptic, Cyrillic
  0x048A, 0x058F, // Cyrillic Extended, Armenian
  0x0903, 0x0FFF, // Devanagari .. Tibetan
  0x1000, 0x1FFF, // Myanmar .. Greek Extended
  0x2071, 0x2071, // SUPERSCRIPT LATIN SMALL LETTER I
  0x207F, 0x207F, // SUPERSCRIPT LATIN SMALL LETTER N
  0x2090, 0x209C, // Latin subscripts
  0x2102, 0x2102, // DOUBLE-STRUCK CAPITAL C
  0x2107, 0x2107, // EULER CONSTANT
  0x210A, 0x2113, // Letterlike symbols
  0x2115, 0x2115, // DOUBLE-STRUCK CAPITAL N
  0x2119, 0x211D, // Letterlike symbols
  0x2124, 0x2124, // DOUBLE-STRUCK CAPITAL Z
  0x2126, 0x2126, // OHM SIGN
  0x2128, 0x2128, // BLACK-LETTER CAPITAL Z
  0x212A, 0x212D, // Letterlike symbols
  0x212F, 0x2139, // Letterlike symbols
  0x213C, 0x213F, // Letterlike symbols
  0x2145, 0x2149, // Double-struck italics
  0x214E, 0x214E, // TURNED SMALL F
  0x2C00, 0x2FFF, // Glagolitic .. CJK radicals
  0x3005, 0x3007, // Ideographic iteration and number marks
  0x3021, 0x3029, // Hangzhou numerals
  0x3031, 0x3035, // Kana repeat marks
  0x3038, 0x303C, // Hangzhou numerals, masu mark
  0x3041, 0xD7FF, // Kana, CJK, Hangul
  0xF900, 0xFB17, // CJK compatibility, Latin and Armenian ligatures
  0xFF21, 0xFF3A, // Fullwidth A-Z
  0xFF41, 0xFF5A, // Fullwidth a-z
  0xFF66, 0xFFDC, // Halfwidth kana, halfwidth Hangul
  0x10000, 0x107FF, // Linear B .. Cypriot syllabary
  0x11000, 0x1342F, // Brahmi .. Egyptian hieroglyphs
  0x16800, 0x16F9F, // Bamum supplement .. Miao
  0x1B000, 0x1B2FF, // Kana supplement and extended
  0x1D400, 0x1D7CB, // Mathematical alphanumerics, stopping before the digits
  0x20000, 0x2FA1F, // CJK unified ideographs extensions
];
