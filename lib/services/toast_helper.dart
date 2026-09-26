import 'package:flutter/flutter.dart';
import 'package:flutter/material.dart';

class ToastHelper {
  static void showToast(String message, {BuildContext? context}) {
    // If a context is available and valid, we can show a SnackBar or custom overlay.
    // Alternatively, if called globally without context, you can integrate Fluttertoast or log it.
    debugPrint('[Toast]: $message');
  }
}
