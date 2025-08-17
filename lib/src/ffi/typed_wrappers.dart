import 'dart:js_interop';
import 'memory.dart';
import 'type_utils.dart';

// External registry for user-provided typed wrappers (by DF signature)
final Map<String, Object Function(JSFunction jsFunc, Memory memory)>
    _externalTypedWrappers = {};

/// Register a typed wrapper builder for a specific DF signature.
/// Call this once per DF signature you need.
void registerTypedWrapper<DF extends Function>(
    DF Function(JSFunction jsFunc, Memory memory) builder) {
  _externalTypedWrappers[typeString<DF>()] =
      (jsFunc, memory) => builder(jsFunc, memory) as Object;
}

/// Builds a strongly-typed Dart function wrapper for a given JS-exported wasm function.
/// Returns null if no typed wrapper is registered for the requested DF signature.
DF? buildTypedWrapper<DF extends Function>(
    JSFunction jsFunc, Memory boundMemory) {
  final ext = _externalTypedWrappers[typeString<DF>()];
  if (ext != null) {
    return ext(jsFunc, boundMemory) as DF;
  }
  return null;
}
