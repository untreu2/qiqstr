import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../lib/src/rust/frb_generated.dart';

Future<void> initializeNativeRust() async {
  final extension = Platform.isMacOS ? 'dylib' : 'so';
  final path = Platform.environment['QIQSTR_NATIVE_LIBRARY'] ??
      '${Directory.current.path}/rust/target/debug/librust_lib_qiqstr.$extension';
  await RustLib.init(externalLibrary: ExternalLibrary.open(path));
}
