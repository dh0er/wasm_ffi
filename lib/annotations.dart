/// An annotation to explicitly register a specific function signature with
/// `registerTypedWrapper`.
///
/// Pass the signature as a string matching the generic passed to
/// `.asFunction<...>()`.
///
/// Usage in a consuming package:
///
/// ```dart
/// @WasmRegisterSignature('int Function(int, double)')
/// late final _foo = _fooPtr.asFunction<int Function(int, double)>();
/// ```
class WasmRegisterSignature {
  final String signature;
  const WasmRegisterSignature(this.signature);
}

/// A file-level annotation that instructs the generator to scan the whole file
/// for `.asFunction<...>()` patterns and register every discovered signature.
///
/// Usage:
///
/// ```dart
/// @WasmRegisterAllSignatures()
/// // ... rest of file
/// ```
class WasmRegisterAllSignatures {
  const WasmRegisterAllSignatures();
}
