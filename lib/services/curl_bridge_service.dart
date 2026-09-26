import 'dart:ffi' as ffi;
import 'dart:io';
import 'ffi_native_types.dart';
import 'mesh_log_provider.dart';

// Signature definitions matching our C curl wrapper bindings
typedef CurlInitC = ffi.Pointer<ffi.Void> Function();
typedef CurlInitDart = ffi.Pointer<ffi.Void> Function();

typedef CurlFetchC = ffi.Int32 Function(ffi.Pointer<ffi.Void> curlHandle, ffi.Pointer<ffi.Char> url, ffi.Pointer<ffi.Char> outBuffer, ffi.Int32 bufferSize);
typedef CurlFetchDart = int Function(ffi.Pointer<ffi.Void> curlHandle, ffi.Pointer<ffi.Char> url, ffi.Pointer<ffi.Char> outBuffer, int bufferSize);

typedef CurlCleanupC = ffi.Void Function(ffi.Pointer<ffi.Void> curlHandle);
typedef CurlCleanupDart = void Function(ffi.Pointer<ffi.Void> curlHandle);

/// Dart FFI wrapper interfacing directly with libcurl via C bindings
class CurlBridgeService {
  static final CurlBridgeService _instance = CurlBridgeService._internal();
  factory CurlBridgeService() => _instance;
  CurlBridgeService._internal();

  ffi.DynamicLibrary? _lib;
  CurlInitDart? _curlInit;
  CurlFetchDart? _curlFetch;
  CurlCleanupDart? _curlCleanup;
  
  ffi.Pointer<ffi.Void>? _curlHandle;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  void initialize() {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid || Platform.isLinux) {
        _lib = ffi.DynamicLibrary.open('libcurl_bridge.so');
      } else {
        _lib = ffi.DynamicLibrary.process();
      }

      _curlInit = _lib!.lookup<ffi.NativeFunction<CurlInitC>>('native_curl_init').asFunction<CurlInitDart>();
      _curlFetch = _lib!.lookup<ffi.NativeFunction<CurlFetchC>>('native_curl_fetch').asFunction<CurlFetchDart>();
      _curlCleanup = _lib!.lookup<ffi.NativeFunction<CurlCleanupC>>('native_curl_cleanup').asFunction<CurlCleanupDart>();

      _curlHandle = _curlInit!();
      _isInitialized = true;
      MeshLogProvider().addLog('libcurl FFI native bridge initialized successfully.');
    } catch (e) {
      MeshLogProvider().addLog('Failed to initialize libcurl FFI bindings: $e');
    }
  }

  /// Performs a high-performance native URL transfer request using libcurl
  String? fetchUrl(String url) {
    if (!_isInitialized || _curlHandle == null || _curlFetch == null) {
      MeshLogProvider().addLog('CurlBridge not initialized.');
      return null;
    }

    try {
      final urlPointer = url.toNativeUtf8();
      final bufferSize = 8192;
      final bufferPointer = ffi.calloc<ffi.Char>(bufferSize);

      final result = _curlFetch!(_curlHandle!, urlPointer, bufferPointer, bufferSize);
      
      String? responseContent;
      if (result == 0) {
        responseContent = bufferPointer.cast<Utf8>().toDartString();
      } else {
        MeshLogProvider().addLog('libcurl fetch failed with error code: $result');
      }

      ffi.calloc.free(urlPointer);
      ffi.calloc.free(bufferPointer);
      return responseContent;
    } catch (e) {
      MeshLogProvider().addLog('Error executing native curl fetch: $e');
      return null;
    }
  }

  void dispose() {
    if (_curlHandle != null && _curlCleanup != null) {
      _curlCleanup!(_curlHandle!);
      _curlHandle = null;
      _isInitialized = false;
      MeshLogProvider().addLog('libcurl handle cleaned up.');
    }
  }
}
