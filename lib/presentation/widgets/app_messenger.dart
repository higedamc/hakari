import 'package:flutter/material.dart';

/// Root [ScaffoldMessenger] key, wired into [MaterialApp] by HakariApp.
///
/// Using a global key lets async flows surface SnackBars without holding a
/// BuildContext across await gaps.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows [message] as a floating SnackBar on the root messenger.
void showAppSnackBar(String message, {SnackBarAction? action}) {
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: const Duration(seconds: 4),
      ),
    );
}
