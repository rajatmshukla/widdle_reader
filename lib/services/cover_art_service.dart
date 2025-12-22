import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class CoverArtService {
  static final CoverArtService _instance = CoverArtService._internal();
  factory CoverArtService() => _instance;
  CoverArtService._internal();
  static const Map<String, String> _headers = {
    'User-Agent': 'WiddleReader/1.5.0 (rajatmshukla@gmail.com)',
  };

  /// Search Open Library for cover art based on title and author
  Future<Uint8List?> fetchCoverFromOpenLibrary(String title, String? author, String audiobookPath) async {
    try {
      /*
      // 1. Check if cover.jpg already exists in the folder
      // Removed: Permission issue on Android 11+
      final existingCover = File(p.join(audiobookPath, 'cover.jpg'));
      if (await existingCover.exists()) {
        debugPrint('🎨 Found existing cover.jpg for $title');
        return await existingCover.readAsBytes();
      }
      */

      // 2. Search Open Library API
      final query = author != null && author.isNotEmpty ? '$title $author' : title;
      final encodedQuery = Uri.encodeComponent(query);
      final searchUrl = 'https://openlibrary.org/search.json?q=$encodedQuery&limit=1';
      
      debugPrint('🎨 [OpenLibrary] Searching: $searchUrl');
      final response = await http.get(Uri.parse(searchUrl), headers: _headers).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docs = data['docs'] as List;
        
        if (docs.isNotEmpty) {
          final firstDoc = docs[0];
          final coverId = firstDoc['cover_i'];
          
          if (coverId != null) {
            final imageUrl = 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
            debugPrint('🎨 [OpenLibrary] Found cover ID $coverId, downloading: $imageUrl');
            
            final imageResponse = await http.get(Uri.parse(imageUrl), headers: _headers).timeout(const Duration(seconds: 15));
            if (imageResponse.statusCode == 200) {
              final bytes = imageResponse.bodyBytes;
              
              /*
              // 3. Cache to disk (DISABLED: Permission issue)
              try {
                await existingCover.writeAsBytes(bytes);
                debugPrint('🎨 Cached cover art to ${existingCover.path}');
              } catch (e) {
                debugPrint('🎨 Error caching cover art: $e');
              }
              */
              
              return bytes;
            }
          } else {
            debugPrint('🎨 [OpenLibrary] No cover ID found for search result');
          }
        } else {
          debugPrint('🎨 [OpenLibrary] No search results found for: $query');
        }
      } else {
        debugPrint('🎨 [OpenLibrary] Search failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🎨 [OpenLibrary] Error: $e');
    }
    
    return null;
  }
  
  /// Helper to check if a folder has a cover.jpg
  Future<File?> getExistingCoverFile(String folderPath) async {
    final file = File(p.join(folderPath, 'cover.jpg'));
    if (await file.exists()) return file;
    return null;
  }

  /// Search Open Library for a list of potential covers
  Future<List<Map<String, String>>> searchCovers(String title, String? author) async {
    try {
      final query = author != null && author.isNotEmpty ? '$title $author' : title;
      final encodedQuery = Uri.encodeComponent(query);
      final searchUrl = 'https://openlibrary.org/search.json?q=$encodedQuery&limit=20';
      
      debugPrint('🎨 [OpenLibrary] Searching list: $searchUrl');
      final response = await http.get(Uri.parse(searchUrl), headers: _headers).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docs = data['docs'] as List;
        final results = <Map<String, String>>[];
        
        for (var doc in docs) {
          final coverId = doc['cover_i'];
          if (coverId != null) {
            results.add({
              'id': coverId.toString(),
              'title': doc['title'] ?? 'Unknown',
              'author': (doc['author_name'] as List?)?.first ?? 'Unknown',
              'thumbUrl': 'https://covers.openlibrary.org/b/id/$coverId-M.jpg',
              'largeUrl': 'https://covers.openlibrary.org/b/id/$coverId-L.jpg',
            });
          }
        }
        return results;
      }
    } catch (e) {
      debugPrint('🎨 [OpenLibrary] Search list error: $e');
    }
    return [];
  }

  /// Download a specific image and NOT save it as cover.jpg (return bytes for caching)
  Future<Uint8List?> downloadAndSaveCover(String url, String audiobookPath) async {
    try {
      debugPrint('🎨 [OpenLibrary] Manual download: $url');
      final response = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 20));
      
      if (response.statusCode == 200) {
        if (response.headers['content-type']?.contains('image') ?? false) {
          final bytes = response.bodyBytes;
          /*
          // DISABLED: Permission issue on Android 11+
          final coverFile = File(p.join(audiobookPath, 'cover.jpg'));
          await coverFile.writeAsBytes(bytes);
          debugPrint('🎨 Manually saved cover art to ${coverFile.path}');
          */
          return bytes;
        } else {
          debugPrint('🎨 [OpenLibrary] Manual download error: Response is not an image (${response.headers['content-type']})');
          throw Exception("The downloaded file is not an image.");
        }
      } else {
        debugPrint('🎨 [OpenLibrary] Manual download failed with status: ${response.statusCode}');
        throw Exception("Server returned status code: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('🎨 [OpenLibrary] Manual download error: $e');
      rethrow;
    }
  }
}
