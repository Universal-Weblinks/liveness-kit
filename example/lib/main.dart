import 'dart:io';

import 'package:flutter/material.dart';
import 'package:liveness_kit/liveness_kit.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'liveness_kit',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF8531D1),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LivenessResult? _result;

  Future<void> _run() async {
    final result = await Navigator.of(context).push<LivenessResult>(
      MaterialPageRoute(
        builder: (_) => LivenessCapture(
          // Anything the platform could not do is worth knowing about: a
          // device with no detector is silent otherwise.
          onDiagnostic: (error, stack) => debugPrint('liveness: $error'),
          // Only shown after two failed attempts, and only because this is
          // given.
          onEscape: () => debugPrint('liveness: skipped'),
          showDiagnostics: true,
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('liveness_kit')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (result is LivenessPassed) ...[
                ClipOval(
                  child: Image.file(
                    File(result.photoPath),
                    width: 180,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                switch (result) {
                  null => 'No check run yet.',
                  LivenessPassed() => 'Passed. Photo saved to disk.',
                  LivenessCancelled() => 'Cancelled.',
                  LivenessSkipped() => 'Skipped after repeated attempts.',
                  LivenessUnavailable(:final reason) =>
                    'Unavailable on this device.\n${reason ?? ''}',
                },
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _run,
                child: const Text('Run the check'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
