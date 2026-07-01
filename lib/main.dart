import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
void main() {
  runApp(const VoiceCalculatorApp());
}

class VoiceCalculatorApp extends StatelessWidget {
  const VoiceCalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Calculator',
      home: VoiceCalculatorHome(),
    );
  }
}

class VoiceCalculatorHome extends StatefulWidget {
  @override
  State<VoiceCalculatorHome> createState() => _VoiceCalculatorHomeState();
}

class _VoiceCalculatorHomeState extends State<VoiceCalculatorHome> {
  final TextEditingController inputController = TextEditingController();
  String result = "0";

  stt.SpeechToText speech =
stt.SpeechToText();
  bool isListening = false;
  Future<void> startListening() async {
    print("Mic button clicked");

  bool available = await speech.initialize();

  print("Speech available: $available");

  if (available) {
    setState(() {
      isListening = true;
    });

    speech.listen(
      listenFor: const Duration(seconds: 10),
      partialResults: true,
      listenMode: stt.ListenMode.dictation,  
      onResult: (result) {
        print("WORDS: ${result.recognizedWords}");

        setState(() {
          String text = result.recognizedWords.toLowerCase();

          text = text.replaceAll("zero", "0");
          text = text.replaceAll("one", "1");
          text = text.replaceAll("two", "2");
          text = text.replaceAll("three", "3");
          text = text.replaceAll("four", "4");
          text = text.replaceAll("five", "5");
          text = text.replaceAll("six", "6");
          text = text.replaceAll("seven", "7");
          text = text.replaceAll("eight", "8");
          text = text.replaceAll("nine", "9");
          text = text.replaceAll("ten", "10");

          text = text.replaceAll("1 hundred", "100");
          text = text.replaceAll("2 hundred", "200");
          text = text.replaceAll("3 hundred", "300");
          text = text.replaceAll("4 hundred", "400");
          text = text.replaceAll("5 hundred", "500");
          text = text.replaceAll("6 hundred", "600");
          text = text.replaceAll("7 hundred", "700");
          text = text.replaceAll("8 hundred", "800");
          text = text.replaceAll("9 hundred", "900");

          text = text.replaceAll("1 thousand", "1000");
          text = text.replaceAll("2 thousand", "2000");
          text = text.replaceAll("3 thousand", "3000");
          text = text.replaceAll("4 thousand", "4000");
          text = text.replaceAll("5 thousand", "5000");
          text = text.replaceAll("6 thousand", "6000");
          text = text.replaceAll("7 thousand", "7000");
          text = text.replaceAll("8 thousand", "8000");
          text = text.replaceAll("9 thousand", "9000");

          text = text.replaceAll(" plus ", "+");
          text = text.replaceAll(" minus ", "-");
          text = text.replaceAll(" multiply ", "*");
          text = text.replaceAll(" multiplied by ", "*");
          text = text.replaceAll(" into ", "*");
          text = text.replaceAll(" times ", "*");
          text = text.replaceAll(" divide ", "/");
          text = text.replaceAll(" divided by ", "/");

          inputController.text = text;

        });
      },
    );
  }
}

  double performOperation(double a, double b, String op) {
    switch (op) {
      case "+":
        return a + b;
      case "-":
        return a - b;
      case "*":
        return a * b;
      case "/":
        return a / b;
      default:
        throw Exception("Unknown operator");
    }
  }

  void calculate() {
    try {
      String expression = inputController.text.replaceAll(" ", "");

      double answer = 0;

      if (expression.contains("+") &&
         !expression.contains("-") &&
         !expression.contains("*") &&
         !expression.contains("/")) {

        List<String> parts = expression.split("+");

        for (String part in parts) {
          answer += double.parse(part);
        }

      } else if (expression.contains("-") &&
          !expression.contains("+") &&
          !expression.contains("*") &&
          !expression.contains("/")) {

        List<String> parts = expression.split("-");

        answer = double.parse(parts[0]);

        for (int i = 1; i < parts.length; i++) {
          answer -= double.parse(parts[i]);
        }

      } else if (expression.contains("*") &&
          !expression.contains("+") &&
          !expression.contains("-") &&
          !expression.contains("/")) {

        List<String> parts = expression.split("*");

        answer = 1;

        for (String part in parts) {
          answer *= double.parse(part);
        }

      } else if (expression.contains("/") &&
          !expression.contains("+") &&
          !expression.contains("-") &&
          !expression.contains("*")) {

        List<String> parts = expression.split("/");

        answer = double.parse(parts[0]);

        for (int i = 1; i < parts.length; i++) {
          answer /= double.parse(parts[i]);
        }

      } else {
        result = "Mixed operations coming soon!";
        return;
      }

      setState(() {
        if (answer == answer.toInt()) {
          result = answer.toInt().toString();
        } else {
          result = answer.toString();
        }
      });

    } catch (e) {
      setState(() {
        result = "Invalid Input";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Voice Calculator"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: inputController,
              decoration: const InputDecoration(
                labelText: "Enter expression",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: calculate,
              child: const Text("Calculate"),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: startListening,
              child: const Text("🎤 Speak"),
            ),

            const SizedBox(height: 30),

            Text(
              "Result: $result",
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



        