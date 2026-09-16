/// Converts free-form speech recognition output into a clean math expression
/// that [ExpressionEngine] can evaluate.
///
/// Examples:
/// - "twenty five plus thirty"            -> "25+30"
/// - "three point five multiplied by two" -> "3.5*2"
/// - "20 percent of 150"                  -> "(20/100)*150"
/// - "square root of 81"                  -> "sqrt 81"
/// - "two thousand five hundred"          -> "2500"
/// - "5 factorial"                        -> "5!"
/// - "sin 30"                             -> "sin 30"
library;

class VoiceParser {
  // ------------------------------------------------------------------
  // Number vocabulary
  // ------------------------------------------------------------------

  static const Map<String, int> _units = {
    'zero': 0,
    'oh': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };

  static const Map<String, int> _tensMap = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  static const Map<String, int> _scales = {
    'hundred': 100,
    'thousand': 1000,
    'million': 1000000,
    'billion': 1000000000,
    'trillion': 1000000000000,
  };

  // ------------------------------------------------------------------
  // Trigger phrases to strip before parsing ("calculate what is 5+5")
  // ------------------------------------------------------------------

  static final List<RegExp> _triggerPatterns = [
    RegExp(r'\bwhat\s+is\b'),
    RegExp(r"\bwhat'?s\b"),
    RegExp(r'\bhow\s+much\s+is\b'),
    RegExp(r'\bhow\s+much\b'),
    RegExp(r'\btell\s+me\b'),
    RegExp(r'\bcalculate\b'),
    RegExp(r'\bcalculator\b'),
    RegExp(r'\bcompute\b'),
    RegExp(r'\bevaluate\b'),
    RegExp(r'\bsolve\b'),
    RegExp(r'\bequals?\b'),
    RegExp(r'\bthe\s+answer\b'),
    RegExp(r'\bplease\b'),
  ];

  // ------------------------------------------------------------------
  // Main entry point
  // ------------------------------------------------------------------

  static String parse(String rawSpeech) {
    var s = rawSpeech.toLowerCase().trim();
    if (s.isEmpty) return '';

    // Normalize punctuation: keep math symbols (incl. '/' — the recognizer
    // writes dictated division literally, e.g. "8/7/2/3"), drop the rest.
    s = s.replaceAll(RegExp(r'[–—_]'), ' ');
    s = s.replaceAll(RegExp(r'[^a-z0-9.+\-*^()%!/\s]'), ' ');

    // Strip trigger phrases and hesitation filler words.
    for (final p in _triggerPatterns) {
      s = s.replaceAll(p, ' ');
    }
    s = s.replaceAll(RegExp(r'\b(um+|uh+|umm+|uhh+|er|ah+)'), ' ');
    s = _collapseSpaces(s);

    // 1) Convert number words / digit sequences into numerals.
    s = _convertNumbers(s);

    // 1b) Spoken division between numbers: "8 upon 3", "9 by 3",
    //     "6 slash 2", "7 over 4". Loop so chains work: "8 upon 3 upon 2".
    final spokenDiv = RegExp(
        r'(\d+(?:\.\d+)?)\s+(?:upon|slash|by|over)\s+(\d+(?:\.\d+)?)');
    var prevDiv = '';
    while (prevDiv != s) {
      prevDiv = s;
      s = s.replaceAllMapped(
          spokenDiv, (m) => '${m.group(1)}/${m.group(2)}');
    }

    // 2) Pattern-based phrases that need the digits we just produced.
    //    (String.replaceAll does not support $1 group refs — use Mapped.)
    s = s.replaceAllMapped(
        RegExp(r'(\d+(?:\.\d+)?)\s*percent\s+of\s*'),
        (m) => '(${m.group(1)}/100)*');
    s = s.replaceAllMapped(
        RegExp(r'(\d+(?:\.\d+)?)\s*percent'), (m) => '${m.group(1)}%');
    s = s.replaceAllMapped(RegExp(r'factorial\s+of\s+(\d+(?:\.\d+)?)'),
        (m) => '${m.group(1)}!');
    s = s.replaceAllMapped(
        RegExp(r'(\d+(?:\.\d+)?)\s*factorial'), (m) => '${m.group(1)}!');
    s = s.replaceAllMapped(
        RegExp(r'(\d+(?:\.\d+)?)\s*squared\b'), (m) => '${m.group(1)}^2');
    s = s.replaceAllMapped(
        RegExp(r'(\d+(?:\.\d+)?)\s*cubed\b'), (m) => '${m.group(1)}^3');

    // 3) Word operators & functions (multi-word phrases first).
    const phraseOps = <String, String>{
      'to the power of': '^',
      'to the power': '^',
      'raised to the power of': '^',
      'raised to': '^',
      'multiplied by': '*',
      'multiplied with': '*',
      'multiply by': '*',
      'multiplied': '*',
      'multiply': '*',
      'divided by': '/',
      'divide by': '/',
      'divided': '/',
      'divide': '/',
      'square root of': 'sqrt',
      'square root': 'sqrt',
      'cube root of': 'cbrt',
      'cube root': 'cbrt',
      'natural log': 'ln',
      'log base 10': 'log',
      'arc sine': 'asin',
      'arc cosine': 'acos',
      'arc tangent': 'atan',
      'inverse sine': 'asin',
      'inverse cosine': 'acos',
      'inverse tangent': 'atan',
      'open bracket': '(',
      'close bracket': ')',
      'open paren': '(',
      'close paren': ')',
      'open parenthesis': '(',
      'close parenthesis': ')',
    };

    final wordOps = <String, String>{
      'times': '*',
      'into': '*',
      'x': '*',
      'over': '/',
      'upon': '/',
      'slash': '/',
      'plus': '+',
      'add': '+',
      'and': '+',
      'minus': '-',
      'subtract': '-',
      'less': '-',
      'negative': '-',
      'power': '^',
      'mod': '%',
      'modulo': '%',
      'modulus': '%',
      'remainder': '%',
      'percent': '%',
      'factorial': '!',
      'point': '.',
      'sine': 'sin',
      'sin': 'sin',
      'cosine': 'cos',
      'cos': 'cos',
      'tangent': 'tan',
      'tan': 'tan',
      'asin': 'asin',
      'acos': 'acos',
      'atan': 'atan',
      'arcsine': 'asin',
      'arccosine': 'acos',
      'arctangent': 'atan',
      'logarithm': 'log',
      'log': 'log',
      'ln': 'ln',
      'sqrt': 'sqrt',
      'root': 'sqrt',
      'cbrt': 'cbrt',
      'exponent': 'exp',
      'exp': 'exp',
      'absolute': 'abs',
      'abs': 'abs',
      'euler': 'e',
      'e': 'e',
      'pi': 'pi',
      'of': ' ',
      'by': ' ',
      'is': ' ',
      'are': ' ',
      'the': ' ',
      'to': ' ',
      'a': ' ',
      'an': ' ',
      'answer': ' ',
      'result': ' ',
      'value': ' ',
      'total': ' ',
    };

    // Phrase replacements need \b boundaries to avoid partial hits.
    final phraseKeys = phraseOps.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in phraseKeys) {
      s = s.replaceAll(RegExp('\\b${RegExp.escape(key)}\\b'), phraseOps[key]!);
    }
    for (final entry in wordOps.entries) {
      s = s.replaceAll(RegExp('\\b${RegExp.escape(entry.key)}\\b'),
          ' ${entry.value} ');
    }

    s = _collapseSpaces(s).trim();

    // Compact spacing around operator symbols so "2 + 3" becomes "2+3".
    // Function calls like "sqrt 81" keep their space (no symbol involved).
    s = s.replaceAllMapped(RegExp(r'\s*([+\-*/^%!])\s*'), (m) => m.group(1)!);

    return s;
  }

  // ------------------------------------------------------------------
  // Number word conversion
  // ------------------------------------------------------------------

  static bool _isNumberish(String w) =>
      _units.containsKey(w) ||
      _tensMap.containsKey(w) ||
      _scales.containsKey(w) ||
      w == 'point' ||
      RegExp(r'^\d+(\.\d+)?$').hasMatch(w);

  static String _convertNumbers(String s) {
    final words = s.split(' ').where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    var i = 0;

    while (i < words.length) {
      final w = words[i];
      if (!_isNumberish(w)) {
        out.add(w);
        i++;
        continue;
      }

      // Accumulate one (possibly compound) number using the classic
      // total/current algorithm so "two thousand five hundred" = 2500.
      var total = 0;
      var current = 0;
      var decimal = false;
      var fracDigits = '';
      var sawAny = false;
      var sawScale = false;

      void flushCurrentToTotal() {
        total += current;
        current = 0;
      }

      while (i < words.length) {
        final t = words[i];
        // "three hundred AND forty two" -> one number (342), but
        // "five AND three" -> 5+3. So skip "and" only after a scale word.
        if (t == 'and' && sawAny && sawScale && !decimal) {
          i++;
          continue;
        }
        if (t == 'point') {
          if (decimal) break; // second "point" ends the number
          decimal = true;
          sawAny = true;
          i++;
          continue;
        }
        if (RegExp(r'^\d+$').hasMatch(t)) {
          if (decimal) {
            fracDigits += t;
          } else {
            current = current * _pow10(t.length) + int.parse(t);
          }
          sawAny = true;
          i++;
          continue;
        }
        if (RegExp(r'^\d+\.\d+$').hasMatch(t) || RegExp(r'^\.\d+$').hasMatch(t)) {
          final parts = t.split('.');
          final intPart = parts[0].isEmpty ? '0' : parts[0];
          if (decimal) {
            fracDigits += parts[0] + (parts.length > 1 ? parts[1] : '');
          } else {
            current = current * _pow10(intPart.length) + int.parse(intPart);
            if (parts.length > 1 && parts[1].isNotEmpty) {
              decimal = true;
              fracDigits = parts[1];
            }
          }
          sawAny = true;
          i++;
          continue;
        }
        if (_scales.containsKey(t)) {
          final scale = _scales[t]!;
          sawScale = true;
          if (scale >= 1000) {
            // thousand / million / billion: commit what we have so far.
            flushCurrentToTotal();
            if (total == 0) total = 1; // "thousand" alone = 1000
            total *= scale;
          } else {
            // hundred: multiplies only the current group.
            current = (current == 0 ? 1 : current) * scale;
          }
          sawAny = true;
          i++;
          continue;
        }
        if (_units.containsKey(t) || _tensMap.containsKey(t)) {
          final v = _units[t] ?? _tensMap[t]!;
          if (decimal) {
            fracDigits += v.toString();
          } else {
            current += v;
          }
          sawAny = true;
          i++;
          continue;
        }
        break;
      }
      flushCurrentToTotal();

      if (sawAny) {
        if (decimal && fracDigits.isNotEmpty) {
          out.add('$total.${fracDigits.isEmpty ? '0' : fracDigits}');
        } else {
          out.add(total.toString());
        }
      }
    }

    return out.join(' ');
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  static String _collapseSpaces(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ');
}
