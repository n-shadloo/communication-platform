import 'package:communication_platform/app/design_system/app_text_direction.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

// Each literal below carries the character's Unicode name and bidi class in a
// trailing comment, because the glyph alone does not say which block it came
// from and several of these differ only by block.
const persian = 'سلام'; // سلام
const hebrew = 'שלום'; // שלום
const persianDigits = '۱۲۳'; // ۱۲۳, bidi class EN
const arabicIndicDigits = '١٢٣'; // ١٢٣, bidi class AN
const formsA = 'ﭐ'; // ARABIC LETTER ALEF WASLA ISOLATED FORM, AL
const formsB = 'ﻲ'; // ARABIC LETTER YEH FINAL FORM, AL
const samaritan = 'ࠀ'; // SAMARITAN LETTER ALAF, R
const mandaic = 'ࡀ'; // MANDAIC LETTER HALQA, R
const syriacSupplement = 'ࡠ'; // SYRIAC LETTER MALAYALAM NGA, AL
const arabicExtendedA = 'ࢠ'; // ARABIC LETTER BEH WITH SMALL V BELOW, AL
const arabicExtendedB = 'ࡰ'; // ARABIC LETTER ALEF WITH ATTACHED FATHA, AL
const thaana = 'ހ'; // THAANA LETTER HAA, AL
const nko = 'ߊ'; // NKO LETTER A, R
const hebrewNsm = '֑'; // HEBREW ACCENT ETNAHTA, NSM
const arabicNsm = 'ً'; // ARABIC FATHATAN, NSM
const arabicNumberSign = '؀'; // ARABIC NUMBER SIGN, AN
const thumbsUp = '\u{1F44D}';
// Built from code points rather than written as literals: an isolate initiator
// reorders the source line it appears on, and the analyzer rejects one in a
// string literal as `text_direction_code_point_in_literal`.
final lri = String.fromCharCode(0x2066); // LEFT-TO-RIGHT ISOLATE
final rli = String.fromCharCode(0x2067); // RIGHT-TO-LEFT ISOLATE
final pdi = String.fromCharCode(0x2069); // POP DIRECTIONAL ISOLATE

void main() {
  group('resolveFirstStrongDirection — the cases the prompt names', () {
    test('pure Persian is RTL', () {
      expect(resolveFirstStrongDirection(persian), TextDirection.rtl);
    });

    test('pure Latin is LTR', () {
      expect(resolveFirstStrongDirection('hello'), TextDirection.ltr);
    });

    test('Persian digits then Latin is LTR', () {
      // U+06F0..U+06F9 are class EN. P2 skips them; the first strong character
      // is the `h`. This is the defect that started the change.
      expect(
        resolveFirstStrongDirection('$persianDigits hello'),
        TextDirection.ltr,
      );
    });

    test('Arabic-Indic digits then Latin is LTR', () {
      // U+0660..U+0669 are class AN, and equally not strong.
      expect(
        resolveFirstStrongDirection('$arabicIndicDigits hello'),
        TextDirection.ltr,
      );
    });

    test('Latin digits then Persian is RTL', () {
      expect(resolveFirstStrongDirection('123 $persian'), TextDirection.rtl);
    });

    test('leading punctuation then Persian is RTL', () {
      expect(resolveFirstStrongDirection('«...» $persian'), TextDirection.rtl);
    });

    test('leading emoji then Latin is LTR', () {
      expect(resolveFirstStrongDirection('$thumbsUp hello'), TextDirection.ltr);
    });

    test('Arabic Presentation Forms-B is RTL', () {
      expect(resolveFirstStrongDirection(formsB), TextDirection.rtl);
    });

    test('empty is null', () {
      expect(resolveFirstStrongDirection(''), isNull);
    });

    test('null is null', () {
      expect(resolveFirstStrongDirection(null), isNull);
    });

    test('whitespace only is null', () {
      expect(resolveFirstStrongDirection('   \t\n '), isNull);
    });

    test('digits only is null, in either digit system', () {
      expect(resolveFirstStrongDirection('12345'), isNull);
      expect(resolveFirstStrongDirection(persianDigits), isNull);
      expect(resolveFirstStrongDirection(arabicIndicDigits), isNull);
    });

    test('a bare URL is LTR on its scheme', () {
      expect(
        resolveFirstStrongDirection('https://example.com/a?b=1'),
        TextDirection.ltr,
      );
    });
  });

  group('the bidi classes this resolver claims to handle', () {
    test('R: Hebrew, NKo, Samaritan, Mandaic', () {
      for (final sample in [hebrew, nko, samaritan, mandaic]) {
        expect(
          resolveFirstStrongDirection(sample),
          TextDirection.rtl,
          reason: sample.runes.first.toRadixString(16),
        );
      }
    });

    test('AL: Arabic, Thaana, Syriac Supplement, Extended-A, Extended-B', () {
      for (final sample in [
        persian,
        thaana,
        syriacSupplement,
        arabicExtendedA,
        arabicExtendedB,
        formsA,
        formsB,
      ]) {
        expect(
          resolveFirstStrongDirection(sample),
          TextDirection.rtl,
          reason: sample.runes.first.toRadixString(16),
        );
      }
    });

    test('L: Latin, Greek, Cyrillic, Armenian, CJK, Kana, Hangul', () {
      for (final sample in [
        'hello',
        'αβ', // αβ
        'аб', // аб
        'աբ', // աբ
        '中文', // 中文
        'あい', // あい
        '한국', // 한국
      ]) {
        expect(
          resolveFirstStrongDirection(sample),
          TextDirection.ltr,
          reason: sample.runes.first.toRadixString(16),
        );
      }
    });

    test('NSM marks are skipped, not treated as strong', () {
      expect(
        resolveFirstStrongDirection('$hebrewNsm hello'),
        TextDirection.ltr,
      );
      expect(
        resolveFirstStrongDirection('$arabicNsm hello'),
        TextDirection.ltr,
      );
    });

    test('AN format signs are skipped', () {
      expect(
        resolveFirstStrongDirection('$arabicNumberSign hello'),
        TextDirection.ltr,
      );
    });

    test('ON and WS are skipped', () {
      expect(resolveFirstStrongDirection('  ()[]{}<>!? '), isNull);
      expect(
        resolveFirstStrongDirection('  ()[]{} $persian'),
        TextDirection.rtl,
      );
    });

    test('P2 skips an isolate run and resolves on what follows it', () {
      // The Latin inside the isolate must not decide the paragraph.
      expect(
        resolveFirstStrongDirection('$lri hello $pdi $persian'),
        TextDirection.rtl,
      );
      expect(
        resolveFirstStrongDirection('$rli $persian $pdi hello'),
        TextDirection.ltr,
      );
    });

    test('an unterminated isolate consumes the rest, per P2', () {
      expect(resolveFirstStrongDirection('$lri $persian'), isNull);
    });
  });

  group('why neither prior implementation was kept', () {
    // The regex `_contentDirection` used before this change, reproduced so the
    // comparison is executable rather than asserted in a comment.
    TextDirection? previousRegex(String? text) {
      if (text == null || text.isEmpty) return null;
      final firstStrong = RegExp(r'[֐-ࣿ]|[A-Za-z]').firstMatch(text)?.group(0);
      if (firstStrong == null) return null;
      return RegExp(r'[֐-ࣿ]').hasMatch(firstStrong)
          ? TextDirection.rtl
          : TextDirection.ltr;
    }

    test('the old regex called Persian and Arabic-Indic digits strong', () {
      expect(previousRegex('$persianDigits hello'), TextDirection.rtl);
      expect(previousRegex('$arabicIndicDigits hello'), TextDirection.rtl);
      expect(
        resolveFirstStrongDirection('$persianDigits hello'),
        TextDirection.ltr,
      );
      expect(
        resolveFirstStrongDirection('$arabicIndicDigits hello'),
        TextDirection.ltr,
      );
    });

    test(
      'the old regex saw no direction in either Presentation Forms block',
      () {
        expect(previousRegex(formsA), isNull);
        expect(previousRegex(formsB), isNull);
        expect(resolveFirstStrongDirection(formsA), TextDirection.rtl);
        expect(resolveFirstStrongDirection(formsB), TextDirection.rtl);
      },
    );

    test('intl Bidi.startsWithRtl repeats the digit defect', () {
      // Its _RTL_CHARS is ֑-߿, which contains U+0660..U+0669 and
      // U+06F0..U+06F9.
      expect(intl.Bidi.startsWithRtl('$persianDigits hello'), isTrue);
      expect(intl.Bidi.startsWithRtl('$arabicIndicDigits hello'), isTrue);
      expect(
        resolveFirstStrongDirection('$persianDigits hello'),
        TextDirection.ltr,
      );
    });

    test('intl Bidi hands four RTL scripts to LTR', () {
      // Its _LTR_CHARS claims ࠀ-῿ wholesale.
      for (final sample in [
        samaritan,
        mandaic,
        syriacSupplement,
        arabicExtendedA,
      ]) {
        expect(
          intl.Bidi.startsWithRtl(sample),
          isFalse,
          reason: sample.runes.first.toRadixString(16),
        );
        expect(
          intl.Bidi.startsWithLtr(sample),
          isTrue,
          reason: sample.runes.first.toRadixString(16),
        );
        expect(
          resolveFirstStrongDirection(sample),
          TextDirection.rtl,
          reason: sample.runes.first.toRadixString(16),
        );
      }
    });

    test('intl detectRtlDirectionality is a token count, not first-strong', () {
      // One Persian word among four Latin ones is under the 0.40 threshold, so
      // the package reports LTR even though the first strong character is AL.
      final text = '$persian one two three four';
      expect(intl.Bidi.detectRtlDirectionality(text), isFalse);
      expect(resolveFirstStrongDirection(text), TextDirection.rtl);
    });
  });

  group('composer counter paragraph direction', () {
    double leftOf(TextPainter painter, int start, int end) => painter
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .first
        .left;

    TextPainter paint(String text, TextDirection direction) => TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 14)),
      textDirection: direction,
    )..layout(maxWidth: 1000);

    const counter = '20 / 500';

    test('an RTL paragraph reverses the pair, which is the defect', () {
      final painter = paint(counter, TextDirection.rtl);
      // "500" ends up left of "20": the line reads 500 / 20.
      expect(leftOf(painter, 5, 8), lessThan(leftOf(painter, 0, 2)));
    });

    test('the LTR paragraph the composer now asks for keeps logical order', () {
      final painter = paint(counter, TextDirection.ltr);
      expect(leftOf(painter, 0, 2), lessThan(leftOf(painter, 5, 8)));
    });
  });

  group('what Flutter already handles, recorded so it is not re-fixed', () {
    double leftOf(TextPainter painter, int start, int end) => painter
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .first
        .left;

    test('an embedded Latin URL inside RTL text needs no explicit isolation', () {
      final text = '$persian https://example.com/a?b=1.';
      final painter = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(fontSize: 14)),
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: 1000);
      final urlStart = text.indexOf('https');
      // Persian sits at the right, the URL to its left with its own run intact,
      // and the sentence-final stop at the far left, which is where an RTL
      // paragraph puts it. Flutter runs UAX #9 per paragraph; there is no
      // second direction spliced into this string to isolate from.
      expect(
        leftOf(painter, 0, 4),
        greaterThan(leftOf(painter, urlStart, urlStart + 5)),
      );
      expect(
        leftOf(painter, text.length - 1, text.length),
        lessThan(leftOf(painter, urlStart, urlStart + 5)),
      );
    });
  });
}
