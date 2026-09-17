import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/expression_engine.dart';
import 'core/key_sounds.dart';
import 'core/voice_parser.dart';
import 'widgets/app_logo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const VoiceCalculatorApp());
}

// =============================================================================
// Theme
// =============================================================================

/// A calm, professional palette: indigo primary, teal support, amber accent.
/// No emoji-heavy styling — clean typography, tabular figures, soft shadows.
class AppTheme {
  static const Color _seed = Color(0xFF5B8DEF); // cornflower blue

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0C1524) : const Color(0xFFF3F7FC);
    final surface = isDark ? const Color(0xFF14202F) : Colors.white;

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Saira',
      colorScheme: scheme.copyWith(
        surface: surface,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  // Key styling tokens shared by the keypad.
  static Color keyFill(ColorScheme scheme, KeyRole role) {
    switch (role) {
      case KeyRole.digit:
        return scheme.surfaceContainerHighest.withValues(alpha: 0.65);
      case KeyRole.function:
        return scheme.errorContainer.withValues(alpha: 0.55);
      case KeyRole.operator:
        return scheme.primaryContainer.withValues(alpha: 0.75);
      case KeyRole.sci:
        return scheme.secondaryContainer.withValues(alpha: 0.6);
      case KeyRole.equals:
        return Colors.transparent; // painted by gradient
    }
  }

  static Color keyForeground(ColorScheme scheme, KeyRole role) {
    switch (role) {
      case KeyRole.digit:
        return scheme.onSurface;
      case KeyRole.function:
        return scheme.onErrorContainer;
      case KeyRole.operator:
        return scheme.onPrimaryContainer;
      case KeyRole.sci:
        return scheme.onSecondaryContainer;
      case KeyRole.equals:
        return Colors.white;
    }
  }
}

enum KeyRole { digit, function, operator, sci, equals }

// =============================================================================
// Root widget — owns the theme mode so light/dark actually works.
// =============================================================================

class VoiceCalculatorApp extends StatefulWidget {
  const VoiceCalculatorApp({super.key});

  @override
  State<VoiceCalculatorApp> createState() => _VoiceCalculatorAppState();
}

class _VoiceCalculatorAppState extends State<VoiceCalculatorApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('themeMode') ?? 'dark';
    if (!mounted) return;
    setState(() {
      _themeMode = switch (saved) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
    });
  }

  Future<void> _toggleThemeMode() async {
    final next =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setState(() => _themeMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', next.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Calculator',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: VoiceCalculatorHome(
        isDark: _themeMode != ThemeMode.light,
        onToggleTheme: _toggleThemeMode,
      ),
    );
  }
}

// =============================================================================
// Home
// =============================================================================

class VoiceCalculatorHome extends StatefulWidget {
  const VoiceCalculatorHome({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<VoiceCalculatorHome> createState() => _VoiceCalculatorHomeState();
}

class _VoiceCalculatorHomeState extends State<VoiceCalculatorHome> {
  final ExpressionEngine _engine = ExpressionEngine();
  final TextEditingController _inputController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  static const String _historyKey = 'history';

  String _result = '0';
  String _error = '';
  double? _lastAnswer;
  bool _justEvaluated = false;
  bool _scientificMode = false;

  bool _soundsMuted = false;
  bool _isListening = false;
  // ValueNotifier so live mic volume updates ONLY the mic button's rings,
  // never rebuilding (or shaking) the rest of the screen.
  final ValueNotifier<double> _soundLevel = ValueNotifier(0);
  String _liveTranscript = '';
  // Last clean partial transcript from the recognizer. Some Android engines
  // deliver a FINAL result that concatenates all partials ("88/8/28/2"), so
  // we keep the last clean partial and prefer it when that happens.
  String _lastCleanPartial = '';
  String _voiceMessage = '';

  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _initSounds();
  }

  Future<void> _initSounds() async {
    await KeySoundManager.init();
    if (!mounted) return;
    setState(() => _soundsMuted = KeySoundManager.muted);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _soundLevel.dispose();
    _speech.stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _history = prefs.getStringList(_historyKey) ?? [];
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _history);
  }

  // ---------------------------------------------------------------------------
  // Expression editing
  // ---------------------------------------------------------------------------

  bool get _isWide =>
      MediaQuery.sizeOf(context).width >= 720;

  void _append(String text) {
    if (_error.isNotEmpty) _clearAll();
    if (_justEvaluated) {
      final startsFresh = RegExp(r'^[0-9.πe(√scl]').hasMatch(text) ||
          text == 'ANS';
      if (startsFresh) {
        _inputController.clear();
      }
      _justEvaluated = false;
    }
    final current = _inputController.text;
    final display = _prettyToEngine(text);
    _inputController.text = current + display;
    _moveCursorToEnd();
    _liveEvaluate();
    HapticFeedback.selectionClick();
  }

  /// Key labels shown on buttons, values inserted into the expression.
  String _prettyToEngine(String key) => switch (key) {
        '×' => '×', // engine normalizes to *
        '÷' => '÷', // engine normalizes to /
        '−' => '−', // engine normalizes to -
        '+' => '+',
        '%' => '%',
        '^' => '^',
        '√' => '√',
        'π' => 'π',
        'x²' => '^2',
        'x³' => '^3',
        'n!' => '!',
        'sin' => 'sin(',
        'cos' => 'cos(',
        'tan' => 'tan(',
        'ln' => 'ln(',
        'log' => 'log(',
        'mod' => '%',
        _ => key,
      };

  void _moveCursorToEnd() {
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
  }

  void _deleteLast() {
    if (_justEvaluated || _error.isNotEmpty) {
      _clearAll();
      return;
    }
    final text = _inputController.text;
    if (text.isEmpty) return;
    _inputController.text = text.substring(0, text.length - 1);
    _moveCursorToEnd();
    _liveEvaluate();
    HapticFeedback.selectionClick();
  }

  void _clearAll() {
    setState(() {
      _inputController.clear();
      _result = '0';
      _error = '';
      _justEvaluated = false;
    });
    HapticFeedback.mediumImpact();
  }

  void _reciprocal() {
    if (_justEvaluated && _lastAnswer != null) {
      _inputController.text = '1/(${_inputController.text})';
    } else if (_lastAnswer != null && _inputController.text.isEmpty) {
      _inputController.text =
          '1/(${ExpressionEngine.formatNumber(_lastAnswer!)})';
    } else {
      _append('1/(');
    }
    _moveCursorToEnd();
    _liveEvaluate();
  }

  void _insertAnswer() {
    if (_lastAnswer == null) return;
    _append(ExpressionEngine.formatNumber(_lastAnswer!));
  }

  // ---------------------------------------------------------------------------
  // Evaluation
  // ---------------------------------------------------------------------------

  /// Updates the preview result without touching history.
  void _liveEvaluate() {
    final expr = _inputController.text.trim();
    if (expr.isEmpty) {
      setState(() {
        _result = '0';
        _error = '';
      });
      return;
    }
    try {
      final value = _engine.evaluate(expr);
      setState(() {
        _error = '';
        _result = ExpressionEngine.formatNumber(value);
      });
    } on ExpressionException catch (e) {
      // Incomplete input (e.g. "5+") is normal while typing: keep quiet.
      setState(() {
        _error = e.message.contains('Incomplete') ? '' : e.message;
        if (_error.isEmpty) _result = '';
      });
    } catch (_) {
      setState(() => _error = '');
    }
  }

  /// Full evaluation: shows the result prominently and stores history.
  void _evaluate({bool saveToHistory = true}) {
    final expr = _inputController.text.trim();
    if (expr.isEmpty) return;

    try {
      final value = _engine.evaluate(expr);
      final display = ExpressionEngine.formatNumber(value);
      setState(() {
        _error = '';
        _result = display;
        _lastAnswer = value;
        _justEvaluated = true;
      });
      HapticFeedback.mediumImpact();
      if (saveToHistory) {
        _addHistory(expr, display);
      }
    } on ExpressionException catch (e) {
      setState(() {
        _error = e.message;
        _justEvaluated = false;
      });
      HapticFeedback.vibrate();
    } catch (e) {
      setState(() {
        _error = 'Invalid expression';
        _justEvaluated = false;
      });
    }
  }

  void _addHistory(String expression, String result) {
    setState(() {
      _history.insert(0, '$expression = $result');
      if (_history.length > 100) _history.removeLast();
    });
    _saveHistory();
  }

  // ---------------------------------------------------------------------------
  // Voice recognition
  // ---------------------------------------------------------------------------

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      _setListening(false);
      return;
    }

    setState(() {
      _voiceMessage = '';
      _liveTranscript = '';
    });
    _lastCleanPartial = '';

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _setListening(false);
          }
        },
        onError: (error) {
          _setListening(false);
          if (!mounted) return;
          setState(() {
            _voiceMessage =
                'Voice error: ${error.errorMsg}. Tap the mic to try again.';
          });
        },
      );

      if (!mounted) return;
      if (!available) {
        setState(() {
          _voiceMessage =
              'Speech recognition is not available on this device.';
        });
        return;
      }

      setState(() {
        _isListening = true;
      });
      _soundLevel.value = 0;

      await _speech.listen(
        onSoundLevelChange: (level) {
          // No setState — the button listens to this notifier directly.
          _soundLevel.value = level;
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          // Generous windows: a natural pause while speaking must not cut
          // the utterance short before the user finishes.
          listenFor: Duration(seconds: 30),
          pauseFor: Duration(seconds: 6),
        ),
        onResult: (result) {
          if (!mounted) return;
          // On many Android recognizers, the FINAL result is a concatenation
          // of every partial heard so far ("8" + "8/2" + ... -> "88/8/28/2").
          // The last clean partial is the accurate transcript, so remember it
          // and prefer it whenever the final result looks polluted.
          final words = result.recognizedWords;
          if (result.finalResult) {
            _handleFinalTranscript(words, lastCleanPartial: _lastCleanPartial);
            _lastCleanPartial = '';
          } else if (words.trim().isNotEmpty) {
            _lastCleanPartial = words;
            setState(() => _liveTranscript = words);
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _voiceMessage =
            'Could not start the microphone. Check app permissions.';
      });
    }
  }

  void _setListening(bool listening) {
    if (!mounted) return;
    setState(() {
      _isListening = listening;
    });
    if (!listening) _soundLevel.value = 0;
  }

  void _handleFinalTranscript(String words, {String lastCleanPartial = ''}) {
    // Prefer the clean last partial when the final result looks like the
    // recognizer's concatenated partials (a common Android quirk).
    words = VoiceParser.resolveFinalTranscript(words, lastCleanPartial);

    final spoken = words.toLowerCase().trim();

    // Voice commands (whole utterance only).
    if (RegExp(r'^(please\s+)?(clear|reset|cancel|erase)(\s+all)?[!.]?$')
        .hasMatch(spoken)) {
      _clearAll();
      setState(() {
        _voiceMessage = 'Cleared';
        _liveTranscript = '';
      });
      return;
    }
    if (RegExp(r'^(please\s+)?(delete|backspace)[!.]?$').hasMatch(spoken)) {
      _deleteLast();
      setState(() {
        _voiceMessage = 'Deleted last digit';
        _liveTranscript = '';
      });
      return;
    }

    final parsed = VoiceParser.parse(words);
    final hasMath = RegExp(r'[0-9π!]').hasMatch(parsed) ||
        RegExp(r'\b(sin|cos|tan|log|ln|sqrt|cbrt|exp|abs)\b').hasMatch(parsed);

    if (parsed.trim().isEmpty || !hasMath) {
      setState(() {
        _liveTranscript = words;
        _voiceMessage =
            'Didn\'t catch a calculation. Try "twelve times eight".';
      });
      return;
    }

    setState(() {
      // Show what was heard so the user can trust the recognition.
      _voiceMessage = 'Heard "${words.trim()}"';
      _liveTranscript = '';
      _inputController.text = parsed;
      _moveCursorToEnd();
    });
    _evaluate();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _copyResult() {
    Clipboard.setData(ClipboardData(text: _error.isEmpty ? _result : ''));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Result copied'), duration: Duration(seconds: 1)),
    );
  }

  void _shareResult() {
    final expr = _inputController.text.trim();
    Share.share(
      'Voice Calculator\n$expr = ${_error.isEmpty ? _result : _error}',
    );
  }

  void _openHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _HistorySheet(
        history: _history,
        onSelect: (entry) {
          Navigator.pop(context);
          setState(() {
            _error = '';
            _justEvaluated = false;
            _inputController.text = entry.split('=')[0].trim();
            _moveCursorToEnd();
          });
          _liveEvaluate();
        },
        onDelete: (index) {
          setState(() => _history.removeAt(index));
          _saveHistory();
        },
        onClearAll: () {
          setState(() => _history.clear());
          _saveHistory();
        },
      ),
    );
  }

  void _toggleAngleMode() {
    setState(() {
      _engine.angleMode =
          _engine.angleMode == AngleMode.deg ? AngleMode.rad : AngleMode.deg;
    });
    _liveEvaluate();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildAppBar(context),
      body: Container(
        // Subtle vertical gradient "texture" instead of a flat color.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surface.withValues(alpha: 0.35),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _isWide ? _buildWideBody(scheme) : _buildPortraitBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      leading: const Padding(
        padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
        child: AppLogo(size: 40),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Voice Calculator'),
          Text(
            _engine.angleMode == AngleMode.deg
                ? 'Degrees · M3'
                : 'Radians · M3',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
      actions: [
        // DEG/RAD toggle
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _toggleAngleMode,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _engine.angleMode == AngleMode.deg ? 'DEG' : 'RAD',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _scientificMode ? 'Basic keys' : 'Scientific keys',
          icon: Icon(_scientificMode ? Icons.functions : Icons.calculate_outlined),
          onPressed: () => setState(() => _scientificMode = !_scientificMode),
        ),
        IconButton(
          tooltip: 'History',
          icon: const Icon(Icons.history_rounded),
          onPressed: _openHistory,
        ),
        IconButton(
          tooltip: _soundsMuted ? 'Key sounds off' : 'Key sounds on',
          icon: Icon(
            _soundsMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
          ),
          onPressed: () async {
            final next = !_soundsMuted;
            await KeySoundManager.setMuted(next);
            if (!mounted) return;
            setState(() => _soundsMuted = next);
            if (!next) KeySoundManager.tap();
          },
        ),
        IconButton(
          tooltip: widget.isDark ? 'Light mode' : 'Dark mode',
          icon: Icon(
            widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
          onPressed: widget.onToggleTheme,
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            if (value == 'about') {
              _showAbout(context);
            } else if (value == 'share') {
              _shareResult();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'share', child: Text('Share result')),
            PopupMenuItem(value: 'about', child: Text('About')),
          ],
        ),
      ],
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Voice Calculator',
      applicationVersion: '1.0.0',
      applicationIcon: const AppLogo(size: 56),
      children: const [
        SizedBox(height: 8),
        Text(
          'A professional calculator with clear voice recognition, a full '
          'scientific engine, and history.\n\n'
          'Try saying: "twelve point five times four", "square root of 81", '
          '"20 percent of 150".\n\n'
          'Developed by Abinaya M.',
        ),
      ],
    );
  }

  // Portrait: display on top, centered voice button, keypad below.
  Widget _buildPortraitBody() {
    return Column(
      children: [
        Expanded(flex: _scientificMode ? 4 : 5, child: _buildDisplay()),
        _buildVoiceSection(),
        Expanded(flex: _scientificMode ? 9 : 8, child: _buildKeypad()),
      ],
    );
  }

  // Wide (tablet/landscape): display left, keypad right.
  Widget _buildWideBody(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildDisplay()),
              _buildVoiceSection(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(width: 420, child: _buildKeypad()),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Display panel
  // ---------------------------------------------------------------------------

  Widget _buildDisplay() {
    final scheme = Theme.of(context).colorScheme;
    final hasExpression = _inputController.text.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: widget.isDark ? 0.35 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Expression input line.
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: IntrinsicWidth(
                child: TextField(
                  controller: _inputController,
                  keyboardType: TextInputType.none,
                  showCursor: true,
                  autofocus: false,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.5,
                    color: scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(color: scheme.outline),
                  ),
                  onChanged: (_) => _liveEvaluate(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Result / error line.
          Expanded(
            flex: 4,
            child: _error.isNotEmpty
                ? _ErrorBanner(message: _error)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (hasExpression && !_justEvaluated)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            '=',
                            style: TextStyle(
                              fontSize: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _result,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.5,
                              color: _justEvaluated
                                  ? scheme.primary
                                  : scheme.onSurface.withValues(alpha: 0.75),
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: IconButton(
                          tooltip: 'Copy result',
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: _copyResult,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Voice strip (mic + live transcript)
  // ---------------------------------------------------------------------------

  // Centered voice section: big mic button on top, caption below.
  // The button has a FIXED footprint — pulse rings are painted behind it,
  // so nothing ever shifts or "shakes" while listening.
  Widget _buildVoiceSection() {
    final scheme = Theme.of(context).colorScheme;
    final showLive = _isListening && _liveTranscript.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _VoiceMicButton(
            listening: _isListening,
            level: _soundLevel,
            onTap: _toggleListening,
          ),
          // Fixed-height caption area: 1 or 2 lines never resize the layout.
          SizedBox(
            height: 44,
            width: double.infinity,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Padding(
                  key: ValueKey(showLive ? _liveTranscript : _voiceMessage),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    showLive
                        ? '“${_liveTranscript.trim()}”'
                        : (_voiceMessage.isNotEmpty
                            ? _voiceMessage
                            : 'Tap the mic and speak — say “twelve times eight”'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      fontStyle:
                          showLive ? FontStyle.italic : FontStyle.normal,
                      fontWeight:
                          showLive ? FontWeight.w600 : FontWeight.w400,
                      color: showLive
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Keypad
  // ---------------------------------------------------------------------------

  Widget _buildKeypad() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxHeight > 520 ? 10.0 : 6.0;
        return Column(
          children: [
            if (_scientificMode)
              Expanded(
                flex: 3,
                child: _KeyGrid(
                  rows: const [
                    ['sin', 'cos', 'tan', '^', '√'],
                    ['ln', 'log', 'x²', 'x³', 'n!'],
                    ['π', 'e', 'ANS', '1/x', 'mod'],
                  ],
                  columns: 5,
                  role: KeyRole.sci,
                  fontSize: 16,
                  gap: gap,
                  onKey: _handleKey,
                ),
              ),
            Expanded(
              flex: _scientificMode ? 5 : 12,
              child: _KeyGrid(
                rows: const [
                  ['AC', '⌫', '%', '÷'],
                  ['7', '8', '9', '×'],
                  ['4', '5', '6', '−'],
                  ['1', '2', '3', '+'],
                  ['(', ')', '0', '.', '='],
                ],
                columns: 4,
                role: KeyRole.digit,
                fontSize: 22,
                gap: gap,
                onKey: _handleKey,
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleKey(String key) {
    switch (key) {
      case 'AC':
        KeySoundManager.clear();
        _clearAll();
      case '⌫':
        KeySoundManager.tap();
        _deleteLast();
      case '=':
        KeySoundManager.confirm();
        _evaluate();
      case 'ANS':
        KeySoundManager.tap();
        _insertAnswer();
      case '1/x':
        KeySoundManager.tap();
        _reciprocal();
      default:
        KeySoundManager.tap();
        _append(key);
    }
  }
}

// =============================================================================
// Key grid & buttons
// =============================================================================

class _KeyGrid extends StatelessWidget {
  const _KeyGrid({
    required this.rows,
    required this.columns,
    required this.role,
    required this.fontSize,
    required this.gap,
    required this.onKey,
  });

  final List<List<String>> rows;
  final int columns;
  final KeyRole role;
  final double fontSize;
  final double gap;
  final void Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: gap),
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < rows[r].length; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: _KeyButton(
                      label: rows[r][c],
                      role: _roleFor(rows[r][c]),
                      fontSize: fontSize,
                      onTap: () => onKey(rows[r][c]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  KeyRole _roleFor(String key) {
    if (key == '=') return KeyRole.equals;
    if (key == 'AC') return KeyRole.function;
    if (role == KeyRole.sci) return KeyRole.sci;
    if (const ['⌫', '%', '÷', '×', '−', '+'].contains(key)) {
      return KeyRole.operator;
    }
    return KeyRole.digit;
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.role,
    required this.fontSize,
    required this.onTap,
  });

  final String label;
  final KeyRole role;
  final double fontSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget child;
    if (role == KeyRole.equals) {
      child = Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [Color(0xFF5B8DEF), Color(0xFF2B5EA7)],
          ),
        ),
        child: _label(Colors.white),
      );
    } else {
      child = Ink(
        decoration: BoxDecoration(
          color: AppTheme.keyFill(scheme, role),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: _label(AppTheme.keyForeground(scheme, role)),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }

  Widget _label(Color color) {
    return Center(
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: color,
        ),
      ),
    );
  }
}

// =============================================================================
// Voice mic button with sound-level pulse
// =============================================================================

class _VoiceMicButton extends StatefulWidget {
  const _VoiceMicButton({
    required this.listening,
    required this.level,
    required this.onTap,
  });

  final bool listening;
  final ValueNotifier<double> level;
  final VoidCallback onTap;

  @override
  State<_VoiceMicButton> createState() => _VoiceMicButtonState();
}

/// A large, centered mic button with a FIXED footprint.
///
/// While listening, expanding ripple rings are PAINTED behind the button —
/// the button itself never changes size, so the surrounding layout never
/// shifts (no shaking). The pulse is time-based, not volume-based, which
/// keeps the motion smooth and calm.
class _VoiceMicButtonState extends State<_VoiceMicButton>
    with SingleTickerProviderStateMixin {
  static const double _size = 84; // the button — always this size
  static const double _ringMax = _size + 34; // max ripple diameter

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = widget.listening;

    final button = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B8DEF), Color(0xFF2B5EA7)],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: listening ? 0.45 : 0.3),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        listening ? Icons.stop_rounded : Icons.mic_none_rounded,
        color: Colors.white,
        size: 38,
      ),
    );

    return SizedBox(
      // Square, fixed stage reserved for button + rings. Never resizes.
      width: _ringMax,
      height: _ringMax,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (listening)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                final t2 = (t + 0.5) % 1;
                return ValueListenableBuilder<double>(
                  valueListenable: widget.level,
                  builder: (context, level, _) {
                    // Louder voice -> brighter rings (0..1).
                    final level01 = (level / 45).clamp(0.0, 1.0);
                    return IgnorePointer(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _ring(scheme, progress: t, boost: level01),
                          _ring(scheme, progress: t2, boost: level01),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onTap,
              child: button,
            ),
          ),
        ],
      ),
    );
  }

  /// A ripple ring at [progress] (0 → just left the button, 1 → faded out).
  /// [boost] brightens rings when your voice is louder — painted only,
  /// so the layout is never affected.
  Widget _ring(ColorScheme scheme,
      {required double progress, double boost = 0}) {
    final size = _size + (_ringMax - _size) * progress;
    final alpha = (0.30 * (1 - progress) + 0.25 * boost * (1 - progress))
        .clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.primary.withValues(alpha: alpha),
          width: 2,
        ),
      ),
    );
  }
}

// =============================================================================
// Error banner & history sheet
// =============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.history,
    required this.onSelect,
    required this.onDelete,
    required this.onClearAll,
  });

  final List<String> history;
  final void Function(String entry) onSelect;
  final void Function(int index) onDelete;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  if (history.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onClearAll();
                      },
                      icon: Icon(
                        Icons.delete_sweep_rounded,
                        size: 20,
                        color: scheme.error,
                      ),
                      label: Text(
                        'Clear all',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 48,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No calculations yet',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                      ),
                      itemBuilder: (context, index) {
                        final entry = history[index];
                        final split = entry.split('=');
                        final expression =
                            split.length > 1 ? split[0].trim() : entry;
                        final result =
                            split.length > 1 ? split.sublist(1).join('=').trim() : '';

                        return ListTile(
                          leading: Icon(
                            Icons.functions_rounded,
                            size: 20,
                            color: scheme.primary,
                          ),
                          title: Text(
                            expression,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            '= $result',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            onPressed: () => onDelete(index),
                          ),
                          onTap: () => onSelect(entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
