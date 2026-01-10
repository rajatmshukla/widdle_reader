import 'package:flutter/material.dart';

/// Global key to access the navigator state from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global key to access the root scaffold messenger state for robust snackbars
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
