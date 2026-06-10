import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Application-wide structured logger.
/// Level: debug in development, warning in release.
/// Usage: `appLog.d('message')` / `appLog.e('message', error: e, stackTrace: s)`
final appLog = Logger(
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: !kReleaseMode,
    printEmojis: !kReleaseMode,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  level: kReleaseMode ? Level.warning : Level.debug,
);
