import 'package:flutter/material.dart';

class ToastHelper {
  static Future<void> showToast(String message, {BuildContext? context}) async {
    debugPrint('[Toast]: $message');
  }
}
