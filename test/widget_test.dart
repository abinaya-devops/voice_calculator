import 'package:flutter_test/flutter_test.dart';
import 'package:voice_calculator/core/expression_engine.dart';
import 'package:voice_calculator/core/voice_parser.dart';

void main() {
  group('ExpressionEngine — basic arithmetic', () {
    final engine = ExpressionEngine();

    test('simple operations', () {
      expect(engine.evaluateToDisplay('2+3'), '5');
      expect(engine.evaluateToDisplay('10-4'), '6');
      expect(engine.evaluateToDisplay('6*7'), '42');
      expect(engine.evaluateToDisplay('8/2'), '4');
      expect(engine.evaluateToDisplay('7%3'), '1');
    });

    test('operator precedence (the old engine got mixed ops wrong)', () {
      expect(engine.evaluateToDisplay('10+5*2'), '20');
      expect(engine.evaluateToDisplay('10-4/2'), '8');
      expect(engine.evaluateToDisplay('2+3*4-6/2'), '11');
      expect(engine.evaluateToDisplay('2*3+4*5'), '26');
    });

    test('parentheses and unary minus', () {
      expect(engine.evaluateToDisplay('(2+3)*4'), '20');
      expect(engine.evaluateToDisplay('-5+10'), '5');
      expect(engine.evaluateToDisplay('2*-3'), '-6');
      expect(engine.evaluateToDisplay('-(2+3)'), '-5');
    });

    test('implicit multiplication', () {
      expect(engine.evaluateToDisplay('2(3+4)'), '14');
      expect(engine.evaluateToDisplay('2pi'), '6.2831853072');
      expect(engine.evaluateToDisplay('(1+2)(3+4)'), '21');
    });

    test('powers and factorial', () {
      expect(engine.evaluateToDisplay('2^10'), '1024');
      expect(engine.evaluateToDisplay('2^3^2'), '512'); // right associative
      expect(engine.evaluateToDisplay('5!'), '120');
      expect(engine.evaluateToDisplay('3!+4!'), '30');
      expect(engine.evaluateToDisplay('9^0.5'), '3');
    });

    test('percent semantics like a real calculator', () {
      expect(engine.evaluateToDisplay('50%'), '0.5');
      expect(engine.evaluateToDisplay('200+10%'), '220');
      expect(engine.evaluateToDisplay('200-10%'), '180');
      expect(engine.evaluateToDisplay('200*10%'), '20');
      // "10%50" is modulo in this grammar, not percentage-of.
      expect(engine.evaluateToDisplay('10%50'), '10');
    });

    test('scientific functions (degrees by default)', () {
      expect(engine.evaluateToDisplay('sin(30)'), '0.5');
      expect(engine.evaluateToDisplay('cos(60)'), '0.5');
      expect(engine.evaluateToDisplay('tan(45)'), '1');
      expect(engine.evaluateToDisplay('sqrt(81)'), '9');
      expect(engine.evaluateToDisplay('sqrt 144'), '12');
      expect(engine.evaluateToDisplay('log(100)'), '2');
      expect(engine.evaluateToDisplay('ln(e)'), '1');
      expect(engine.evaluateToDisplay('abs(-7)'), '7');
      expect(engine.evaluateToDisplay('cbrt(27)'), '3');
    });

    test('radian mode', () {
      engine.angleMode = AngleMode.rad;
      expect(engine.evaluateToDisplay('sin(pi/2)'), '1');
      engine.angleMode = AngleMode.deg;
    });

    test('unicode and word normalization', () {
      expect(engine.evaluateToDisplay('2×3'), '6');
      expect(engine.evaluateToDisplay('10÷4'), '2.5');
      expect(engine.evaluateToDisplay('1,000+1'), '1001');
      expect(engine.evaluateToDisplay('2 plus 3'), '5');
      expect(engine.evaluateToDisplay('6 times 7'), '42');
      expect(engine.evaluateToDisplay('10 divided by 4'), '2.5');
      expect(engine.evaluateToDisplay('square root of 16'), '4');
    });

    test('error handling', () {
      expect(
        () => engine.evaluate('5/0'),
        throwsA(isA<ExpressionException>()),
      );
      expect(
        () => engine.evaluate('sqrt(-4)'),
        throwsA(isA<ExpressionException>()),
      );
      expect(
        () => engine.evaluate('2+'),
        throwsA(isA<ExpressionException>()),
      );
      // Unclosed parens are auto-closed (calculator-style).
      expect(engine.evaluateToDisplay('(2+3'), '5');
      expect(
        () => engine.evaluate('hello'),
        throwsA(isA<ExpressionException>()),
      );
    });

    test('clean number formatting', () {
      expect(ExpressionEngine.formatNumber(0.1 + 0.2), '0.3');
      expect(ExpressionEngine.formatNumber(10.0), '10');
      expect(ExpressionEngine.formatNumber(-0.5), '-0.5');
      expect(
        ExpressionEngine.formatNumber(123456.789),
        '123456.789',
      );
    });
  });

  group('VoiceParser — speech to expression', () {
    test('digit operators', () {
      expect(VoiceParser.parse('2 plus 3'), '2+3');
      expect(VoiceParser.parse('6 times 7'), '6*7');
      expect(VoiceParser.parse('10 divided by 2'), '10/2');
      expect(VoiceParser.parse('9 minus 4'), '9-4');
    });

    test('trigger phrases are stripped', () {
      expect(VoiceParser.parse('what is 2 plus 3'), '2+3');
      expect(VoiceParser.parse('calculate 6 times 7'), '6*7');
      expect(VoiceParser.parse('please tell me 5 plus 5'), '5+5');
    });

    test('compound numbers', () {
      expect(VoiceParser.parse('twenty five plus thirty'), '25+30');
      expect(VoiceParser.parse('two thousand five hundred'), '2500');
      expect(VoiceParser.parse('three hundred and forty two'), '342');
      expect(VoiceParser.parse('one million'), '1000000');
    });

    test('decimals via point', () {
      expect(VoiceParser.parse('three point five times two'), '3.5*2');
      expect(VoiceParser.parse('0.5 plus 0.25'), '0.5+0.25');
    });

    test('dictated slash chains are kept (regression: 8/7/2/3)', () {
      // Speech recognizers often dictate division literally as slashes.
      // The parser must NOT strip them (they used to merge into 8723).
      expect(VoiceParser.parse('8/7/2/3+6+3/4'), '8/7/2/3+6+3/4');
    });

    test('spoken division: upon / by / slash, incl. chains', () {
      expect(VoiceParser.parse('8 upon 3'), '8/3');
      expect(VoiceParser.parse('9 by 3'), '9/3');
      expect(VoiceParser.parse('6 slash 2'), '6/2');
      expect(VoiceParser.parse('8 upon 3 upon 2'), '8/3/2');
      expect(VoiceParser.parse('100 by 5 plus 1'), '100/5+1');
    });

    test('scientific commands', () {
      expect(VoiceParser.parse('square root of 81'), 'sqrt 81');
      expect(VoiceParser.parse('sin 30'), 'sin 30');
      expect(VoiceParser.parse('log of 100'), 'log 100');
      expect(VoiceParser.parse('5 factorial'), '5!');
      expect(VoiceParser.parse('factorial of 6'), '6!');
      expect(VoiceParser.parse('2 to the power of 10'), '2^10');
      expect(VoiceParser.parse('20 percent of 150'), '(20/100)*150');
    });

    test('leftover filler words removed', () {
      final parsed = VoiceParser.parse('what is the answer to 4 times 5');
      expect(parsed, '4*5');
    });
  });

  group('End-to-end: speech -> parser -> engine', () {
    final engine = ExpressionEngine();

    double evalSpeech(String speech) =>
        engine.evaluate(VoiceParser.parse(speech));

    test('twelve times eight', () {
      expect(ExpressionEngine.formatNumber(evalSpeech('twelve times eight')),
          '96');
    });

    test('two point five plus one point five', () {
      expect(
          ExpressionEngine.formatNumber(
              evalSpeech('two point five plus one point five')),
          '4');
    });

    test('square root of eighty one', () {
      expect(
        ExpressionEngine.formatNumber(
          engine.evaluate(VoiceParser.parse('square root of eighty one')),
        ),
        '9',
      );
    });

    test('hundred divided by four', () {
      expect(
        ExpressionEngine.formatNumber(evalSpeech('hundred divided by four')),
        '25',
      );
    });

    test('dictated slash chain evaluates correctly (user-reported bug)', () {
      // "8/7/2/3+6+3/4" spoken: must divide, not merge digits.
      final value = engine.evaluate('8/7/2/3+6+3/4');
      expect(value, closeTo(8 / 7 / 2 / 3 + 6 + 3 / 4, 1e-9));
    });

    test('eight upon three (spoken division end-to-end)', () {
      expect(
        ExpressionEngine.formatNumber(evalSpeech('eight upon three')),
        '2.6666666667',
      );
    });
  });

  group('resolveFinalTranscript — Android concatenated-partials bug', () {
    // Android recognizers sometimes deliver a final result that is every
    // partial chained together: "8" + "8/2" -> "88/8/28/2".
    test('polluted final falls back to the clean last partial', () {
      expect(
        VoiceParser.resolveFinalTranscript('88/8/28/2', '8/2'),
        '8/2',
      );
      expect(
        VoiceParser.resolveFinalTranscript('55+5+5+115+11-5+11-35+11-3',
            '5+11-3'),
        '5+11-3',
      );
    });

    test('genuine longer final is kept', () {
      // Partial caught only part of the sentence; the final extends it.
      expect(
        VoiceParser.resolveFinalTranscript('5+11-3', '5+11-'),
        '5+11-3',
      );
      expect(
        VoiceParser.resolveFinalTranscript('twenty five plus two', 'twenty five'),
        'twenty five plus two',
      );
    });

    test('equal or clean finals pass through', () {
      expect(VoiceParser.resolveFinalTranscript('8/2', '8/2'), '8/2');
      expect(VoiceParser.resolveFinalTranscript('8/2', ''), '8/2');
    });
  });
}
