import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _libName = 'opencc';

void main(List<String> args) async {
  await build(args, _builder);
}

Future<void> _builder(BuildInput input, BuildOutputBuilder output) async {
  // Hook có thể được gọi ở pass không build code asset -> bỏ qua, tránh ném khi
  // truy cập input.config.code.
  if (!input.config.buildCodeAssets) return;

  final targetOS = input.config.code.targetOS;
  final libFilename = targetOS.dylibFileName(_libName); // libopencc.dylib
  final outLibFile = File.fromUri(input.outputDirectory.resolve(libFilename));

  // Dùng binary LOCAL/VENDORED thay vì download remote.
  final src = _localLib(input);
  File(src).copySync(outLibFile.path);
  stderr.writeln("opencc hook: dùng lib '$src' -> '${outLibFile.path}'");

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/lib_$_libName.dart',
      linkMode: DynamicLoadingBundled(),
      file: outLibFile.uri,
    ),
  );
}

String _localLib(BuildInput input) {
  final os = input.config.code.targetOS;

  // iOS: chọn đúng slice theo SDK (device vs simulator) — 2 dylib khác nhau.
  if (os == OS.iOS) {
    final sim = input.config.code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    final sub = sim ? 'ios-sim' : 'ios-device';
    final f = File.fromUri(
      input.packageRoot.resolve('native/$sub/libopencc.dylib'),
    );
    if (f.existsSync()) return f.path;
    throw StateError('Thiếu native/$sub/libopencc.dylib trong package opencc.');
  }

  // Android: chọn .so self-contained theo ABI (vendored).
  if (os == OS.android) {
    final arch = input.config.code.targetArchitecture;
    final abi = switch (arch) {
      Architecture.arm64 => 'arm64-v8a',
      Architecture.arm => 'armeabi-v7a',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError('Android arch $arch chưa hỗ trợ'),
    };
    final f = File.fromUri(
      input.packageRoot.resolve('native/android/$abi/libopencc.so'),
    );
    if (f.existsSync()) return f.path;
    throw StateError('Thiếu native/android/$abi/libopencc.so trong package opencc.');
  }

  // macOS host: dùng dylib brew (chỉ để spike trên máy).
  if (os == OS.macOS) {
    const candidates = [
      '/opt/homebrew/opt/opencc/lib/libopencc.dylib',
      '/opt/homebrew/lib/libopencc.dylib',
      '/usr/local/opt/opencc/lib/libopencc.dylib',
      '/usr/local/lib/libopencc.dylib',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    throw StateError('Không thấy libopencc.dylib — chạy: brew install opencc');
  }

  throw UnsupportedError('OS $os chưa hỗ trợ (Android làm sau).');
}
