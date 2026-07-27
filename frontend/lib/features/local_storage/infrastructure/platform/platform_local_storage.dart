export 'platform_local_storage_stub.dart'
    if (dart.library.io) 'platform_local_storage_native.dart'
    if (dart.library.js_interop) 'platform_local_storage_web.dart';
