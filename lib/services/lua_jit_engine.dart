import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'mesh_log_provider.dart';

// FFI typedefs for LuaJIT C bindings
typedef LuaEvalC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> code);
typedef LuaEvalDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> code);

typedef LuaActionC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> code, ffi.Pointer<Utf8> action, ffi.Pointer<Utf8> itemId);
typedef LuaActionDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> code, ffi.Pointer<Utf8> action, ffi.Pointer<Utf8> itemId);

typedef LuaSearchC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> code, ffi.Pointer<Utf8> query);
typedef LuaSearchDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> code, ffi.Pointer<Utf8> query);

class LuaJitEngine {
  static final LuaJitEngine _instance = LuaJitEngine._internal();
  factory LuaJitEngine() => _instance;
  LuaJitEngine._internal();

  late final ffi.DynamicLibrary _lib;
  late final LuaEvalDart _luaEval;
  late final LuaActionDart _luaAction;
  late final LuaSearchDart _luaSearch;
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    try {
      _lib = Platform.isAndroid
          ? ffi.DynamicLibrary.open('libluajit_engine.so')
          : ffi.DynamicLibrary.process();

      _luaEval = _lib.lookup<ffi.NativeFunction<LuaEvalC>>('lua_eval_code').asFunction();
      _luaAction = _lib.lookup<ffi.NativeFunction<LuaActionC>>('lua_execute_action').asFunction();
      _luaSearch = _lib.lookup<ffi.NativeFunction<LuaSearchC>>('lua_execute_search').asFunction();

      _initialized = true;
      MeshLogProvider().addLog("LuaJIT Native Engine initialized successfully.");
    } catch (e) {
      MeshLogProvider().addLog("Failed to load LuaJIT Native Library: $e");
    }
  }

  String eval(String luaCode) {
    if (!_initialized) initialize();
    if (!_initialized) return '{"status": "error", "message": "LuaJIT engine not initialized"}';

    final codePtr = luaCode.toNativeUtf8();
    try {
      final resPtr = _luaEval(codePtr);
      return resPtr.toDartString();
    } finally {
      calloc.free(codePtr);
    }
  }

  String executeAction(String luaCode, String action, String itemId) {
    if (!_initialized) initialize();
    if (!_initialized) return '{"items": []}';

    final codePtr = luaCode.toNativeUtf8();
    final actionPtr = action.toNativeUtf8();
    final idPtr = itemId.toNativeUtf8();
    try {
      final resPtr = _luaAction(codePtr, actionPtr, idPtr);
      return resPtr.toDartString();
    } finally {
      calloc.free(codePtr);
      calloc.free(actionPtr);
      calloc.free(idPtr);
    }
  }

  String search(String luaCode, String query) {
    if (!_initialized) initialize();
    if (!_initialized) return '{"items": []}';

    final codePtr = luaCode.toNativeUtf8();
    final queryPtr = query.toNativeUtf8();
    try {
      final resPtr = _luaSearch(codePtr, queryPtr);
      return resPtr.toDartString();
    } finally {
      calloc.free(codePtr);
      calloc.free(queryPtr);
    }
  }
}
