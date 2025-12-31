import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p_pkg;

class NativeScannerEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int length;
  final int lastModified;

  NativeScannerEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.length,
    required this.lastModified,
  });

  factory NativeScannerEntry.fromMap(Map<dynamic, dynamic> map) {
    return NativeScannerEntry(
      name: map['name'] as String,
      path: map['path'] as String,
      isDirectory: map['isDirectory'] as bool,
      length: map['length'] as int,
      lastModified: map['lastModified'] as int,
    );
  }
}

class NativeScanner {
  static const MethodChannel _channel = MethodChannel('com.widdlereader.app/android_auto');

  /// Launches the system folder picker (SAF) and returns the selected tree Uri.
  static Future<String?> pickFolder() async {
    if (!Platform.isAndroid) return null;
    try {
      final String? result = await _channel.invokeMethod('pickFolder');
      return result;
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.pickFolder Error: ${e.message}");
      return null;
    }
  }

  /// Launches the system file creator (SAF) and returns the created file Uri.
  static Future<String?> createFile(String fileName, String mimeType) async {
    if (!Platform.isAndroid) return null;
    try {
      final String? result = await _channel.invokeMethod('createFile', {
        'fileName': fileName,
        'mimeType': mimeType,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.createFile Error: ${e.message}");
      return null;
    }
  }

  /// Gets the human-readable display name for a SAF Uri or File path.
  static Future<String?> getDisplayName(String path) async {
    if (!Platform.isAndroid) return p_pkg.basename(path);
    try {
      final String? result = await _channel.invokeMethod('getDisplayName', {'path': path});
      return result ?? p_pkg.basename(path);
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.getDisplayName Error: ${e.message}");
      return p_pkg.basename(path);
    }
  }

  /// Lists directory contents using native Java File API or DocumentFile (SAF).
  static Future<List<NativeScannerEntry>> listDirectory(String path) async {
    if (!Platform.isAndroid) {
      final dir = Directory(path);
      if (!await dir.exists()) return [];
      
      final List<NativeScannerEntry> results = [];
      await for (final entity in dir.list(followLinks: false)) {
        final stat = await entity.stat();
        results.add(NativeScannerEntry(
          name: p_pkg.basename(entity.path),
          path: entity.path,
          isDirectory: entity is Directory,
          length: stat.size,
          lastModified: stat.modified.millisecondsSinceEpoch,
        ));
      }
      return results;
    }

    try {
      final List<dynamic>? result = await _channel.invokeMethod('listDirectory', {'path': path});
      if (result == null) return [];
      
      return result.map((item) => NativeScannerEntry.fromMap(item as Map<dynamic, dynamic>)).toList();
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.listDirectory Error: ${e.message}");
      return [];
    }
  }

  /// Recursively scans for directories containing audio files using native code.
  static Future<List<String>> recursiveScan(String path) async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? result = await _channel.invokeMethod('recursiveScan', {'path': path});
      if (result == null) return [];
      return result.cast<String>();
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.recursiveScan Error: ${e.message}");
      return [];
    }
  }

  /// Reads bytes from a file or SAF Uri.
  static Future<Uint8List?> readBytes(String path) async {
    if (!Platform.isAndroid) {
      final file = File(path);
      if (await file.exists()) return await file.readAsBytes();
      return null;
    }
    try {
      final result = await _channel.invokeMethod('readBytes', {'path': path});
      if (result != null) return result as Uint8List;
      return null;
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.readBytes Error: ${e.message}");
      return null;
    }
  }

  /// Writes bytes to a file or SAF Uri. Returns the path/uri of the written file.
  static Future<String?> writeBytes(String path, Uint8List bytes, {String? fileName}) async {
    if (!Platform.isAndroid) {
      try {
        final targetFile = fileName != null ? File(p_pkg.join(path, fileName)) : File(path);
        if (!await targetFile.parent.exists()) {
             await targetFile.parent.create(recursive: true);
        }
        await targetFile.writeAsBytes(bytes);
        return targetFile.path;
      } catch(e) {
        debugPrint("NativeScanner.writeBytes Error: $e");
        return null;
      }
    }
    try {
      final String? result = await _channel.invokeMethod('writeBytes', {
        'path': path, 
        'bytes': bytes,
        'fileName': fileName,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.writeBytes Error: ${e.message}");
      return null;
    }
  }

  /// Extracts metadata from a file path or Uri using native MediaMetadataRetriever.
  static Future<Map<String, dynamic>?> getMetadata(String path, {bool extractCover = false}) async {
    if (!Platform.isAndroid) return null;
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getMetadata', {
        'path': path,
        'extractCover': extractCover,
      });
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.getMetadata Error: ${e.message}");
      return null;
    }
  }

  /// Implementation of .nomedia file creation.
  static Future<bool> createNomediaFile(String folderPath) async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod('createNomediaFile', {'path': folderPath});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.createNomediaFile Error: ${e.message}");
      return false;
    }
  }

  /// Implementation of .nomedia file check.
  static Future<bool> hasNomediaFile(String folderPath) async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod('hasNomediaFile', {'path': folderPath});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.hasNomediaFile Error: ${e.message}");
      return false;
    }
  }

  /// Checks if a file or directory exists.
  static Future<bool> exists(String path) async {
    if (!Platform.isAndroid) return await Directory(path).exists() || await File(path).exists();
    try {
      final bool? result = await _channel.invokeMethod('exists', {'path': path});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint("NativeScanner.exists Error: ${e.message}");
      return false;
    }
  }
}
