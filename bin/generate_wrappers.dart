import 'package:wasm_ffi/builder.dart';

// Usage: dart run wasm_ffi:generate_wrappers
Future<void> main(List<String> args) async {
  await generateWasmFfiWrappers();
}
