import 'dart:io';

/// Simple standalone generator that scans `lib/` of the current package for
/// occurrences of the `@WasmRegisterSignature` annotation placed directly
/// above variable initializers ending with `.asFunction<...>()` and emits a
/// `lib/wasm_ffi_signatures.g.dart` file that calls `registerTypedWrapper` for
/// each discovered signature.
///
/// This is intentionally lightweight (regex-based) to avoid pulling in the
/// full analyzer for most users.
Future<void> generateWasmFfiWrappers({String? outFile}) async {
  final repoRoot = Directory.current.path;
  final libDir = Directory('$repoRoot/lib');
  if (!libDir.existsSync()) return;

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      // Avoid writing into and then re-parsing the generated file
      .where((f) => !f.path.endsWith('wasm_ffi_signatures.g.dart'))
      .toList();

  final signatures = <String>{};
  final annotationPattern =
      RegExp(r"WasmRegisterSignature\s*\(\s*'([^']+)'\s*\)");
  final fileLevelPattern = RegExp(r'WasmRegisterAllSignatures\s*\(\s*\)');

  for (final file in dartFiles) {
    final content = await file.readAsString();
    final hasFileLevel = fileLevelPattern.hasMatch(content);

    if (hasFileLevel) {
      int start = 0;
      while (true) {
        final sig = _findNextAsFunctionFrom(content, start);
        if (sig == null) break;
        var cleaned = sig.replaceAll(RegExp(r'\s+'), ' ').trim();
        cleaned = cleaned.replaceAll('ffi.', '');
        signatures.add(cleaned);
        final nextIdx = content.indexOf('asFunction<', start);
        if (nextIdx == -1) break;
        start = nextIdx + 1;
      }
    }

    for (final m in annotationPattern.allMatches(content)) {
      final raw = m.group(1);
      if (raw == null) continue;
      var cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      cleaned = cleaned.replaceAll('ffi.', '');
      signatures.add(cleaned);
    }
  }

  final outPath = outFile ?? '$repoRoot/lib/wasm_ffi_signatures.g.dart';
  final outDir = File(outPath).parent.path;
  final stubPath = '$outDir/wasm_ffi_signatures_stub.g.dart';

  if (signatures.isNotEmpty) {
    final code = _generateRegisterFile(signatures);
    await File(outPath).writeAsString(code);
  }

  // Always ensure a non-web stub exists for conditional imports
  await File(stubPath).writeAsString(_generateStubFile());
}

String? _findNextAsFunctionFrom(String content, int startIndex) {
  const needle = 'asFunction<';
  final idx = content.indexOf(needle, startIndex);
  if (idx == -1) return null;
  int j = idx + needle.length; // position after '<'
  int depth = 1;
  final buf = StringBuffer();
  while (j < content.length && depth > 0) {
    final ch = content[j];
    if (ch == '<') {
      depth++;
      buf.write(ch);
      j++;
      continue;
    }
    if (ch == '>') {
      depth--;
      if (depth == 0) {
        j++; // consume '>' and stop
        break;
      }
      buf.write(ch);
      j++;
      continue;
    }
    buf.write(ch);
    j++;
  }
  // Skip whitespace
  while (j < content.length &&
      (content[j] == ' ' || content[j] == '\n' || content[j] == '\t')) {
    j++;
  }
  if (j >= content.length || content[j] != '(') return null;
  j++;
  while (j < content.length &&
      (content[j] == ' ' || content[j] == '\n' || content[j] == '\t')) {
    j++;
  }
  if (j >= content.length || content[j] != ')') return null;
  return buf.toString();
}

String _generateRegisterFile(Set<String> signatures) {
  final sorted = signatures.toList()..sort();
  final b = StringBuffer();
  b.writeln('// GENERATED FILE - DO NOT EDIT.');
  b.writeln("import 'dart:js_interop';");
  b.writeln("import 'dart:js_interop_unsafe';");
  b.writeln("import 'package:universal_ffi/ffi.dart';");
  b.writeln();
  b.writeln('void registerSignatures() {');
  for (final sig in sorted) {
    final fixed = _fixTypeCasing(sig);
    final ret = _retType(fixed);
    final args = _argTypes(fixed);
    b.writeln('  registerTypedWrapper<$fixed>((jsFunc, memory) {');
    final params = <String>[];
    for (var i = 0; i < args.length; i++) {
      params.add('${_dartParamType(args[i])} a$i');
    }
    b.writeln('    ${_dartReturnType(ret)} wrapper(${params.join(', ')}) {');
    b.writeln(
        "      final apply = ((jsFunc as JSObject).getProperty('apply'.toJS))! as JSFunction;");
    b.writeln('      final argsObj = JSObject();');
    b.writeln("      argsObj.setProperty('length'.toJS, ${args.length}.toJS);");
    for (var i = 0; i < args.length; i++) {
      b.writeln(
          "      argsObj.setProperty('$i'.toJS, ${_toJsArg(args[i], 'a$i')});");
    }
    if (ret == 'void') {
      b.writeln('      apply.callAsFunction(jsFunc, null, argsObj);');
      b.writeln('      return;');
    } else {
      b.writeln('      final r = apply.callAsFunction(jsFunc, null, argsObj);');
      b.writeln(_retConversion(ret));
    }
    b.writeln('    }');
    b.writeln('    return wrapper;');
    b.writeln('  });');
  }
  b.writeln('}');
  return b.toString();
}

String _generateStubFile() {
  final b = StringBuffer();
  b.writeln('// GENERATED STUB FILE - SAFE FOR NON-WEB BUILDS.');
  b.writeln();
  b.writeln('/// No-op on non-web platforms.');
  b.writeln('void registerSignatures() {}');
  return b.toString();
}

String _fixTypeCasing(String sig) {
  const map = {
    'int8': 'Int8',
    'int16': 'Int16',
    'int32': 'Int32',
    'int64': 'Int64',
    'uint8': 'Uint8',
    'uint16': 'Uint16',
    'uint32': 'Uint32',
    'uint64': 'Uint64',
  };
  String out = sig;
  map.forEach((k, v) {
    out = out.replaceAll('Pointer<$k>', 'Pointer<$v>');
    out = out.replaceAll('Pointer<Pointer<$k>>', 'Pointer<Pointer<$v>>');
  });
  return out;
}

String _retType(String sig) {
  final idx = sig.indexOf(' Function(');
  if (idx == -1) return sig;
  return sig.substring(0, idx).trim();
}

List<String> _argTypes(String sig) {
  final start = sig.indexOf(' Function(');
  if (start == -1) return <String>[];
  final open = start + ' Function('.length;
  final end = sig.lastIndexOf(')');
  if (end <= open) return <String>[];
  final inner = sig.substring(open, end).trim();
  if (inner.isEmpty) return <String>[];
  return inner.split(',').map((s) => s.trim()).toList();
}

String _dartParamType(String t) {
  if (t == 'int' || t == 'double' || t == 'bool') return t;
  if (t.startsWith('Pointer<') && t.endsWith('>')) return t;
  return 'Object?';
}

String _dartReturnType(String t) {
  if (t == 'void') return 'void';
  if (t == 'int' || t == 'double' || t == 'bool') return t;
  if (t.startsWith('Pointer<') && t.endsWith('>')) return t;
  return 'Object?';
}

String _toJsArg(String t, String name) {
  if (t == 'int' || t == 'double' || t == 'bool') return '$name.toJS';
  if (t.startsWith('Pointer<') && t.endsWith('>')) return '$name.address.toJS';
  return '$name as JSAny?';
}

String _retConversion(String ret) {
  if (ret == 'void') return '      return;';
  if (ret == 'int') return '      return (r! as JSNumber).toDartInt;';
  if (ret == 'double') return '      return (r! as JSNumber).toDartDouble;';
  if (ret.startsWith('Pointer<') && ret.endsWith('>')) {
    final inner = ret.substring('Pointer<'.length, ret.length - 1);
    return '      final addr = (r! as JSNumber).toDartInt\n      ;\n      return Pointer<$inner>.fromAddress(addr, memory);';
  }
  return '      return r;';
}
