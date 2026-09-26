import 'package:flutter/material.dart';

class ToastHelper {
  static void showToast(String message, {BuildContext? context}) {
    debugPrint('[Toast]: $message');
  }
}
