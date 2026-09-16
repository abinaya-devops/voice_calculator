/// A correct, production-quality math expression engine.
///
/// Supports:
/// - Basic arithmetic: + - * / % (percentage/modulo-aware)
/// - Power: ^ (right associative), unary minus
/// - Parentheses with implicit multiplication: 2(3+4) = 14
/// - Postfix factorial: 5!
/// - Percent: 50% = 0.5, 200+10% = 220 (like a shop calculator)
/// - Scientific functions: sin cos tan asin acos atan sinh cosh tanh
///   ln log sqrt cbrt abs exp floor ceil round
/// - Constants: pi, e
/// - Trig in DEG or RAD mode (like a real scientific calculator)
library;

import 'dart:math' as math;

/// Angle mode for trigonometric functions.
enum AngleMode { deg, rad }

class ExpressionException implements Exception {
  final String message;
  ExpressionException(this.message);

  @override
  String toString() => message;
}

class ExpressionEngine {
  ExpressionEngine({this.angleMode = AngleMode.deg});

  AngleMode angleMode;

  /// Evaluates [input] and returns the numeric result.
  ///
  /// Throws [ExpressionException] with a friendly message on bad input.
  double evaluate(String input) {
    var normalized = _normalize(input);
    if (normalized.isEmpty) {
      throw ExpressionException('Empty expression');
    }

    // Keypad-friendly auto-repair: "sqrt9" -> "sqrt(9" (no space typed),
    // and unclosed "(" are closed automatically, so "sin(30" evaluates.
    normalized = normalized.replaceAllMapped(
      RegExp(
          r'\b(sqrt|cbrt|sin|cos|tan|asin|acos|atan|sinh|cosh|tanh|ln|log|'
          r'exp|abs|floor|ceil|round|sign)(\d)'),
      (m) => '${m.group(1)}(${m.group(2)}',
    );
    var open = 0;
    for (final ch in normalized.codeUnits) {
      if (ch == 0x28) {
        open++;
      } else if (ch == 0x29) {
        open--;
      }
    }
    if (open > 0) {
      normalized += ')' * open;
    }

    final tokens = Tokenizer(normalized).tokenize();
    if (tokens.isEmpty) {
      throw ExpressionException('Invalid expression');
    }
    final parser = _Parser(tokens, this);
    final value = parser.parseExpression();
    parser.expectEnd();
    return value;
  }

  /// Evaluates and returns a clean display string (no trailing .0, no
  /// floating point noise like 0.30000000000000004).
  String evaluateToDisplay(String input) => formatNumber(evaluate(input));

  // ---------------------------------------------------------------------------
  // Normalization: turn what the user typed/said into clean math symbols.
  // ---------------------------------------------------------------------------

  static final RegExp _unicodeOps = RegExp(r'[×✕✖⨯]');
  static final RegExp _divSymbols = RegExp(r'[÷∗∕]');

  String _normalize(String input) {
    var s = input;
    s = s.replaceAll(_unicodeOps, '*');
    s = s.replaceAll(_divSymbols, '/');
    s = s.replaceAll('−', '-'); // unicode minus
    s = s.replaceAll(',', ''); // thousands separators: 1,000 -> 1000
    s = s.replaceAll('π', 'pi').replaceAll('𝜋', 'pi');
    s = s.replaceAll('√', 'sqrt');
    s = s.replaceAll('∛', 'cbrt');
    s = s.toLowerCase();
    s = _collapse(s);

    // Multi-word phrases first (longest keys first so "square root of"
    // wins over "square root"). Bare "sqrt 16" is supported by the parser,
    // so phrases map to the function name without forcing parentheses.
    const phrases = <String, String>{
      'square root of': 'sqrt',
      'square root': 'sqrt',
      'cube root of': 'cbrt',
      'cube root': 'cbrt',
      'to the power of': '^',
      'raised to the power of': '^',
      'raised to': '^',
      'natural log': 'ln',
      'log base 10': 'log',
      'multiplied by': '*',
      'multiplied with': '*',
      'multiply by': '*',
      'divided by': '/',
      'divide by': '/',
    };
    final phraseKeys = phrases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in phraseKeys) {
      s = s.replaceAll(RegExp('\\b${RegExp.escape(k)}\\b'), phrases[k]!);
    }

    // Spoken division: "8 upon 3", "9 by 3", "6 slash 2". Loop so chains
    // like "8 upon 3 upon 2" fully resolve.
    final spokenDiv = RegExp(
        r'(\d+(?:\.\d+)?)\s+(?:upon|slash|by)\s+(\d+(?:\.\d+)?)');
    var prevDiv = '';
    while (prevDiv != s) {
      prevDiv = s;
      s = s.replaceAllMapped(spokenDiv, (m) => '${m.group(1)}/${m.group(2)}');
    }

    // Filler words left over from typed or spoken input.
    s = s.replaceAll(
        RegExp(r'\b(by|of|the|is|are|a|an|to|please)\b'), ' ');

    // Single-word operators and functions.
    const words = <String, String>{
      'plus': '+',
      'minus': '-',
      'times': '*',
      'multiplied': '*',
      'multiply': '*',
      'divided': '/',
      'divide': '/',
      'into': '*',
      'over': '/',
      'x': '*',
      'mod': '%',
      'modulus': '%',
      'modulo': '%',
      'power': '^',
      'pow': '^',
      'sine': 'sin',
      'cosine': 'cos',
      'tangent': 'tan',
      'squared': '^2',
      'cubed': '^3',
    };
    for (final e in words.entries) {
      s = s.replaceAll(
          RegExp('\\b${RegExp.escape(e.key)}\\b'), ' ${e.value} ');
    }

    return _collapse(s).trim();
  }

  static String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  // ---------------------------------------------------------------------------
  // Number formatting
  // ---------------------------------------------------------------------------

  /// Formats a double for display: integers without .0, doubles with up to
  /// 10 significant decimals (trailing zeros trimmed), very large/small
  /// numbers in exponential form.
  static String formatNumber(double value) {
    if (value.isNaN) return 'Error';
    if (value.isInfinite) return value > 0 ? '∞' : '-∞';

    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }

    final abs = value.abs();
    if (abs >= 1e15 || (abs < 1e-9 && abs > 0)) {
      return value.toStringAsExponential(6);
    }

    var s = value.toStringAsFixed(10);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  static double factorial(double n) {
    if (n < 0 || n != n.roundToDouble()) {
      throw ExpressionException('Factorial needs a non-negative whole number');
    }
    if (n > 170) return double.infinity;
    var result = 1.0;
    final k = n.round();
    for (var i = 2; i <= k; i++) {
      result *= i;
    }
    return result;
  }

  /// Trig functions honoring the current angle mode.
  double sin(double x) =>
      angleMode == AngleMode.deg ? math.sin(_toRad(x)) : math.sin(x);
  double cos(double x) =>
      angleMode == AngleMode.deg ? math.cos(_toRad(x)) : math.cos(x);
  double tan(double x) =>
      angleMode == AngleMode.deg ? math.tan(_toRad(x)) : math.tan(x);

  double asin(double x) {
    _domain(x >= -1 && x <= 1, 'asin needs a value between -1 and 1');
    final r = math.asin(x);
    return angleMode == AngleMode.deg ? _toDeg(r) : r;
  }

  double acos(double x) {
    _domain(x >= -1 && x <= 1, 'acos needs a value between -1 and 1');
    final r = math.acos(x);
    return angleMode == AngleMode.deg ? _toDeg(r) : r;
  }

  double atan(double x) {
    final r = math.atan(x);
    return angleMode == AngleMode.deg ? _toDeg(r) : r;
  }

  double log(double x) {
    _domain(x > 0, 'log needs a positive number');
    return math.log(x) / math.ln10;
  }

  double ln(double x) {
    _domain(x > 0, 'ln needs a positive number');
    return math.log(x);
  }

  double sqrt(double x) {
    _domain(x >= 0, 'Cannot take square root of a negative number');
    return math.sqrt(x);
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;

  static void _domain(bool ok, String message) {
    if (!ok) throw ExpressionException(message);
  }
}

// -----------------------------------------------------------------------------
// Tokenizer
// -----------------------------------------------------------------------------

enum TokenType { number, identifier, operator, lparen, rparen, factorial }

class Token {
  final TokenType type;
  final String text;
  final double? number;

  const Token._(this.type, this.text, [this.number]);

  @override
  String toString() => 'Token($type, $text)';
}

class Tokenizer {
  Tokenizer(this._src);
  final String _src;
  int _pos = 0;

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (_pos < _src.length) {
      final ch = _src[_pos];

      if (ch == ' ') {
        _pos++;
        continue;
      }

      if (_isDigit(ch) || (ch == '.' && _peekIsDigit())) {
        final start = _pos;
        while (_pos < _src.length &&
            (_isDigit(_src[_pos]) || _src[_pos] == '.')) {
          _pos++;
        }
        // Exponential notation: 1e5, 2.5e-3
        if (_pos < _src.length &&
            (_src[_pos] == 'e') &&
            _pos + 1 < _src.length &&
            (_isDigit(_src[_pos + 1]) ||
                (_src[_pos + 1] == '-' &&
                    _pos + 2 < _src.length &&
                    _isDigit(_src[_pos + 2])))) {
          // But do NOT swallow "e" when it is the Euler constant:
          // only treat as exponent if digits follow immediately (or -digits).
          _pos++;
          if (_src[_pos] == '-') _pos++;
          while (_pos < _src.length && _isDigit(_src[_pos])) {
            _pos++;
          }
        }
        final text = _src.substring(start, _pos);
        final value = double.tryParse(text);
        if (value == null) {
          throw ExpressionException('Invalid number: $text');
        }
        tokens.add(Token._(TokenType.number, text, value));
        continue;
      }

      if (_isLetter(ch)) {
        final start = _pos;
        while (_pos < _src.length && _isLetterOrDigit(_src[_pos])) {
          _pos++;
        }
        tokens.add(Token._(TokenType.identifier, _src.substring(start, _pos)));
        continue;
      }

      switch (ch) {
        case '(':
          tokens.add(const Token._(TokenType.lparen, '('));
          _pos++;
          continue;
        case ')':
          tokens.add(const Token._(TokenType.rparen, ')'));
          _pos++;
          continue;
        case '!':
          tokens.add(const Token._(TokenType.factorial, '!'));
          _pos++;
          continue;
        case '+':
        case '-':
        case '*':
        case '/':
        case '^':
        case '%':
          tokens.add(Token._(TokenType.operator, ch));
          _pos++;
          continue;
        default:
          throw ExpressionException('Unexpected character: "$ch"');
      }
    }
    return tokens;
  }

  bool _peekIsDigit() =>
      _pos + 1 < _src.length && _isDigit(_src[_pos + 1]);

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isLetter(String c) =>
      (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A) ||
      (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A);
  static bool _isLetterOrDigit(String c) => _isDigit(c) || _isLetter(c);
}

// -----------------------------------------------------------------------------
// Parser (recursive descent)
//
// expression := term (('+'|'-') term)*
// term       := unary (('*'|'/'|'%') unary)*      [% = modulo here]
// unary      := ('-'|'+') unary | power
// power      := postfix ('^' unary)?              [right associative]
// postfix    := primary ('!')*
// primary    := number | constant | function '(' expression ')'
//             | '(' expression ')' | percent
//
// Percent handling: a '%' directly following a number/paren is treated as
// percentage; inside * or / it means divide-by-100, for + and - the parser
// asks the engine for "percent of left operand" semantics.
// -----------------------------------------------------------------------------

class _Parser {
  _Parser(this._tokens, this._engine);
  final List<Token> _tokens;
  final ExpressionEngine _engine;
  int _index = 0;

  static const String _eofSentinel = '␂';

  Token get _current => _index < _tokens.length
      ? _tokens[_index]
      : const Token._(TokenType.operator, _eofSentinel);

  bool _matchOp(String op) {
    if (_current.type == TokenType.operator && _current.text == op) {
      _index++;
      return true;
    }
    return false;
  }

  void expectEnd() {
    if (_index < _tokens.length) {
      throw ExpressionException(
          'Unexpected "${_tokens[_index].text}" in expression');
    }
  }

  double parseExpression() {
    var value = _parseTerm();
    while (true) {
      _lastTermWasPercent = false; // 'value' is now the left operand.

      String? op;
      if (_current.type == TokenType.operator &&
          (_current.text == '+' || _current.text == '-')) {
        op = _current.text;
        _index++;
      } else {
        // Implicit multiplication: 2(3+4), 2pi, (1+2)(3+4), 2sqrt(9)
        final t = _current;
        final implicit = t.type == TokenType.number ||
            t.type == TokenType.identifier ||
            t.type == TokenType.lparen;
        if (!implicit) return value;
        value *= _parseTerm();
        continue;
      }

      final right = _parseTerm();
      final rightWasPercent = _lastTermWasPercent;
      _lastTermWasPercent = false;

      // "200+10%" -> 200 + (10% of 200), like real shop calculators.
      if (op == '+') {
        value += rightWasPercent ? value * right : right;
      } else {
        value -= rightWasPercent ? value * right : right;
      }
    }
  }

  double _parseTerm() {
    var value = _parseUnary();
    while (true) {
      if (_matchOp('*')) {
        value *= _parseUnary();
      } else if (_matchOp('/')) {
        final divisor = _parseUnary();
        if (divisor == 0) {
          throw ExpressionException('Cannot divide by zero');
        }
        value /= divisor;
      } else if (_matchOp('%')) {
        final divisor = _parseUnary();
        if (divisor == 0) {
          throw ExpressionException('Cannot modulo by zero');
        }
        // "a % b" as modulo; the percentage use-case is handled in percent()
        // when % is NOT followed by a value. Here a value follows, so modulo.
        value = value % divisor;
      } else {
        return value;
      }
    }
  }

  double _parseUnary() {
    if (_matchOp('-')) return -_parseUnary();
    if (_matchOp('+')) return _parseUnary();
    return _parsePower();
  }

  double _parsePower() {
    final base = _parsePostfix();
    if (_matchOp('^')) {
      final exponent = _parseUnary(); // right associative: 2^3^2 = 2^(3^2)
      return math.pow(base, exponent).toDouble();
    }
    return base;
  }

  double _parsePostfix() {
    var value = _parsePercent();
    while (_current.type == TokenType.factorial) {
      _index++;
      value = ExpressionEngine.factorial(value);
      if (value.isInfinite) {
        throw ExpressionException('Factorial result is too large');
      }
    }
    return value;
  }

  /// True when the most recently parsed term was a bare percentage
  /// ("10%"), used by parseExpression for percent-of-left semantics.
  bool _lastTermWasPercent = false;

  double _parsePercent() {
    final value = _parsePrimary();
    if (_current.type == TokenType.operator && _current.text == '%') {
      // Look at the token AFTER '%': if a value follows, "a%b" is modulo;
      // otherwise (end, operator, rparen) it is a percentage.
      final next = _index + 1 < _tokens.length ? _tokens[_index + 1] : null;
      final isModulo = next != null &&
          (next.type == TokenType.number ||
              next.type == TokenType.identifier ||
              next.type == TokenType.lparen);
      _index++; // consume '%'
      if (isModulo) {
        _index--; // leave '%' for _parseTerm's modulo branch
        return value;
      }
      _lastTermWasPercent = true;
      return value / 100;
    }
    return value;
  }

  double _parsePrimary() {
    final token = _current;

    switch (token.type) {
      case TokenType.number:
        _index++;
        return token.number!;

      case TokenType.identifier:
        _index++;
        final name = token.text;
        switch (name) {
          case 'pi':
            return math.pi;
          case 'e':
            return math.e;
          case 'sin':
            return _engine.sin(_functionArg());
          case 'cos':
            return _engine.cos(_functionArg());
          case 'tan':
            return _engine.tan(_functionArg());
          case 'asin':
            return _engine.asin(_functionArg());
          case 'acos':
            return _engine.acos(_functionArg());
          case 'atan':
            return _engine.atan(_functionArg());
          case 'sinh':
            return _sinh(_functionArg());
          case 'cosh':
            return _cosh(_functionArg());
          case 'tanh':
            return _tanh(_functionArg());
          case 'ln':
            return _engine.ln(_functionArg());
          case 'log':
            return _engine.log(_functionArg());
          case 'sqrt':
            return _engine.sqrt(_functionArg());
          case 'cbrt':
            return _cbrt(_functionArg());
          case 'abs':
            return _functionArg().abs();
          case 'exp':
            return math.exp(_functionArg());
          case 'floor':
            return _functionArg().floorToDouble();
          case 'ceil':
            return _functionArg().ceilToDouble();
          case 'round':
            return _functionArg().roundToDouble();
          case 'sign':
            return _functionArg().sign.toDouble();
          default:
            throw ExpressionException('Unknown function: "$name"');
        }

      case TokenType.lparen:
        _index++;
        final value = parseExpression();
        if (_current.type != TokenType.rparen) {
          throw ExpressionException('Missing closing ")"');
        }
        _index++;
        return value;

      case TokenType.operator:
        if (token.text == _eofSentinel) {
          throw ExpressionException('Incomplete expression');
        }
        // Handled at unary level; reaching here means two operators in a row.
        throw ExpressionException('Invalid use of "${token.text}"');

      case TokenType.rparen:
        throw ExpressionException('Unexpected ")"');

      case TokenType.factorial:
        throw ExpressionException('Unexpected "!"');
    }
  }

  double _functionArg() {
    if (_current.type == TokenType.lparen) {
      _index++;
      final value = parseExpression();
      if (_current.type != TokenType.rparen) {
        throw ExpressionException('Missing closing ")"');
      }
      _index++;
      return value;
    }
    // Allow "sqrt 9" and "sin 30" without parentheses.
    return _parsePower();
  }

  static double _cbrt(double x) =>
      x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

  // dart:math has no hyperbolic functions — implement them directly.
  static double _sinh(double x) =>
      (math.exp(x) - math.exp(-x)) / 2;
  static double _cosh(double x) =>
      (math.exp(x) + math.exp(-x)) / 2;
  static double _tanh(double x) {
    final e2x = math.exp(2 * x);
    return (e2x - 1) / (e2x + 1);
  }
}
