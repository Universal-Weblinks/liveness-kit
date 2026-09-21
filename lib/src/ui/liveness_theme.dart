import 'package:flutter/material.dart';

/// The colours the capture screen draws itself in.
///
/// The screen is deliberately dark whatever the host app's theme is: the
/// preview is a face lit by the room, and a white page around it both washes
/// the picture out and lights the subject from the wrong side. Only the accent
/// follows the host, so the check looks like it belongs to the app that opened
/// it.
@immutable
class LivenessTheme {
  const LivenessTheme({
    this.background = const Color(0xFF101014),
    this.foreground = Colors.white,
    this.mutedForeground = const Color(0xB3FFFFFF),
    required this.accent,
    this.success = const Color(0xFF2FA35A),
  });

  /// Behind everything, including the app bar.
  final Color background;

  /// Prompts and titles.
  final Color foreground;

  /// Subtitles and detail.
  final Color mutedForeground;

  /// The guide ring while the gestures are being watched, and the button.
  final Color accent;

  /// A cleared challenge, and the ring once the check has passed.
  final Color success;

  /// Takes the accent from the host app's colour scheme.
  factory LivenessTheme.of(BuildContext context) =>
      LivenessTheme(accent: Theme.of(context).colorScheme.primary);

  LivenessTheme copyWith({
    Color? background,
    Color? foreground,
    Color? mutedForeground,
    Color? accent,
    Color? success,
  }) {
    return LivenessTheme(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      accent: accent ?? this.accent,
      success: success ?? this.success,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LivenessTheme &&
      other.background == background &&
      other.foreground == foreground &&
      other.mutedForeground == mutedForeground &&
      other.accent == accent &&
      other.success == success;

  @override
  int get hashCode =>
      Object.hash(background, foreground, mutedForeground, accent, success);
}
