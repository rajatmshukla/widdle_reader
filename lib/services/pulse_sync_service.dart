import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'native_scanner.dart';
import 'package:uuid/uuid.dart';

/// Service for cross-device synchronization via a shared Pulse file.
class PulseSyncService {
  static final PulseSyncService _instance = PulseSyncService._internal();
  factory PulseSyncService() => _instance;
  PulseSyncService._internal();

  final StorageService _storage = StorageService();
  static const String pulseFileName = '.widdle_pulse.json';
  static const String pulseTmpName = '.widdle_pulse.json.tmp';
  
  String? _deviceId;

  /// Initialize the sync service
  Future<void> initialize() async {
    final prefs = await _storage.loadAudiobookFolders(); // Just to ensure prefs ready
    // Get or create unique device ID
    final allData = await _storage.getAllSyncData();
    _deviceId = allData['device_id_sync'] as String?;
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await _storage.injectSyncData({'device_id_sync': _deviceId!});
    }
    
    debugPrint('💓 PulseSyncService initialized (Device ID: $_deviceId)');
  }

  /// Export current state to the Pulse file in the library root
  Future<void> pulseOut() async {
    if (!await _storage.isPulseSyncEnabled()) {
       debugPrint('💓 PulseOut skipped: Sync disabled in settings.');
       return;
    }
    try {
      final rootPath = await _storage.getRootPath();
      if (rootPath == null) {
        debugPrint('💓 PulseOut skipped: No root path set.');
        return;
      }

      debugPrint('💓 Starting PulseOut...');
      final syncData = await _storage.getAllSyncData();
      
      final pulsePayload = {
        'version': 1,
        'deviceId': _deviceId,
        'lastModified': DateTime.now().toIso8601String(),
        'data': syncData,
      };

      final jsonString = jsonEncode(pulsePayload);
      final bytes = utf8.encode(jsonString);

      // Atomic write: .tmp then rename
      // Pass rootPath as path and fileName separately for SAF compatibility
      await NativeScanner.writeBytes(rootPath, bytes, fileName: pulseTmpName);
      // NativeScanner doesn't have a rename, so we just overwrite the main one for now
      // or we can implement a move if the native side supports it.
      // For now, we write directly since SAF writes are somewhat buffered/atomic in many implementations.
      await NativeScanner.writeBytes(rootPath, bytes, fileName: pulseFileName);
      
      debugPrint('💓 PulseOut successful to $rootPath/$pulseFileName');
    } catch (e) {
      debugPrint('💓 PulseOut failed: $e');
    }
  }

  /// Import and merge state from the Pulse file
  Future<void> pulseIn() async {
    if (!await _storage.isPulseSyncEnabled()) {
       debugPrint('💓 PulseIn skipped: Sync disabled in settings.');
       return;
    }
    try {
      final rootPath = await _storage.getRootPath();
      if (rootPath == null) return;

      final bytes = await NativeScanner.readBytes(rootPath, fileName: pulseFileName);
      if (bytes == null || bytes.isEmpty) return;

      final jsonString = utf8.decode(bytes);
      final Map<String, dynamic> remotePulse = jsonDecode(jsonString);
      
      final remoteDeviceId = remotePulse['deviceId'] as String?;
      if (remoteDeviceId == _deviceId) {
        debugPrint('💓 PulseIn: Skipping (File written by this device)');
        return;
      }

      final Map<String, dynamic> remoteData = remotePulse['data'] as Map<String, dynamic>;
      final Map<String, dynamic> localData = await _storage.getAllSyncData();

      debugPrint('💓 PulseIn: Merging remote data...');
      final mergedData = _merge(localData, remoteData);

      await _storage.injectSyncData(mergedData);
      debugPrint('💓 PulseIn: Merge and injection complete.');
    } catch (e) {
      debugPrint('💓 PulseIn failed: $e');
    }
  }

  /// Resolve conflicts between local and remote data
  Map<String, dynamic> _merge(Map<String, dynamic> local, Map<String, dynamic> remote) {
    final merged = Map<String, dynamic>.from(local);

    // Identify all keys in both sets
    final allKeys = {...local.keys, ...remote.keys};

    for (final key in allKeys) {
      final localValue = local[key];
      final remoteValue = remote[key];

      if (localValue == null) {
        merged[key] = remoteValue;
        continue;
      }
      if (remoteValue == null) {
        merged[key] = localValue;
        continue;
      }

      // MERGE LOGIC:
      
      // 1. Progress & Playback (Last Played Timestamp wins)
      if (key.startsWith(StorageService.progressCachePrefix) ||
          key.startsWith(StorageService.lastPositionPrefix)) {
        
        final bookId = _extractBookId(key);
        if (bookId != null) {
          final localTs = local['${StorageService.lastPlayedTimestampPrefix}$bookId'] as int? ?? 0;
          final remoteTs = remote['${StorageService.lastPlayedTimestampPrefix}$bookId'] as int? ?? 0;
          
          if (remoteTs > localTs) {
            merged[key] = remoteValue;
            merged['${StorageService.lastPlayedTimestampPrefix}$bookId'] = remoteTs;
          }
        }
      }
      
      // 2. Statistics & Achievements (Union/Cumulative)
      else if (key.startsWith(StorageService.readingSessionPrefix)) {
        // Sessions are unique by UUID, so we just take the remote one if it doesn't exist locally
        // (Handled by the overall loop if not already merged)
        merged[key] = remoteValue;
      }

      // 3. Reviews (Merge Map) is stored as a JSON string
      else if (key == StorageService.reviewsKey) {
        try {
          final localMap = (localValue is String) ? jsonDecode(localValue) as Map<String, dynamic> : <String, dynamic>{};
          final remoteMap = (remoteValue is String) ? jsonDecode(remoteValue) as Map<String, dynamic> : <String, dynamic>{};
          
          final mergedMap = Map<String, dynamic>.from(localMap);
          
          for (final entry in remoteMap.entries) {
            final bookId = entry.key;
            final remoteReview = entry.value as Map<String, dynamic>;
            
            if (!mergedMap.containsKey(bookId)) {
              mergedMap[bookId] = remoteReview;
            } else {
              // Both have reviews. Compare timestamps if available, or force remote wins.
              // Reviews usually have 'timestamp' field
              final localReview = mergedMap[bookId] as Map<String, dynamic>;
              final localTime = localReview['timestamp'] != null ? DateTime.parse(localReview['timestamp'].toString()) : DateTime(2000);
              final remoteTime = remoteReview['timestamp'] != null ? DateTime.parse(remoteReview['timestamp'].toString()) : DateTime(2000);
              
              if (remoteTime.isAfter(localTime)) {
                mergedMap[bookId] = remoteReview;
              }
            }
          }
           merged[key] = jsonEncode(mergedMap);
        } catch (e) {
          debugPrint('Error merging reviews: $e');
          merged[key] = remoteValue;
        }
      }

      // 4. Bookmarks (Merge List of JSON Maps)
      else if (key.startsWith(StorageService.bookmarksPrefix)) {
        try {
          final localList = (localValue is String) ? jsonDecode(localValue) as List : [];
          final remoteList = (remoteValue is String) ? jsonDecode(remoteValue) as List : [];
          
          if (localList.isNotEmpty && remoteList.isNotEmpty) {
             final mergedMap = <String, Map<String, dynamic>>{};
             // Key by ID
             for (final item in [...localList, ...remoteList]) {
                final mapItem = item as Map<String, dynamic>;
                final id = mapItem['id']?.toString() ?? '${mapItem['position']}_${mapItem['timestamp']}'; // Fallback ID
                mergedMap[id] = mapItem; 
             }
             merged[key] = jsonEncode(mergedMap.values.toList());
          } else if (remoteList.isNotEmpty) {
             merged[key] = remoteValue;
          }
        } catch (e) {
           debugPrint('Error merging bookmarks: $e');
           merged[key] = remoteValue;
        }
      }
      
      // 3. Simple Strings/ID Lists (Merge-Union logic)
      else if (key == StorageService.completedBooksKey) {
        // completedBooksKey is usually List<String>
        if (localValue is List && remoteValue is List) {
           final mergedList = {...localValue, ...remoteValue}.toList();
           merged[key] = mergedList;
        } else {
           merged[key] = remoteValue;
        }
      }
      else if (key == StorageService.unlockedAchievementsKey) {
        // Achievements are stored as a JSON STRING, so we must parse, merge, and re-encode
        try {
          final localList = (localValue is String) ? jsonDecode(localValue) as List : [];
          final remoteList = (remoteValue is String) ? jsonDecode(remoteValue) as List : [];
          
          if (localList.isNotEmpty && remoteList.isNotEmpty) {
            // Merge based on ID
            final mergedMap = <String, Map<String, dynamic>>{};
            
            for (final item in [...localList, ...remoteList]) {
              final mapItem = item as Map<String, dynamic>;
              final id = mapItem['id'] as String;
              
              if (!mergedMap.containsKey(id)) {
                mergedMap[id] = mapItem;
              } else {
                // If both exist, keep the one with earlier unlockedAt (or just keep one)
                // Existing implementation doesn't care much about timestamp diffs for same achievement
              }
            }
            
            merged[key] = jsonEncode(mergedMap.values.toList());
          } else if (remoteList.isNotEmpty) {
            merged[key] = remoteValue;
          }
        } catch (e) {
          debugPrint('Error merging achievements: $e');
          merged[key] = remoteValue; 
        }
      }
      
      // 4. Fallback: Last write wins (Remote wins by default for simplicity in this pass)
      else {
        merged[key] = remoteValue;
      }
    }

    return merged;
  }

  String? _extractBookId(String key) {
    if (key.startsWith(StorageService.progressCachePrefix)) {
      return key.substring(StorageService.progressCachePrefix.length);
    }
    if (key.startsWith(StorageService.lastPositionPrefix)) {
      return key.substring(StorageService.lastPositionPrefix.length);
    }
    return null;
  }
}
