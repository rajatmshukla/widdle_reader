import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../models/audiobook.dart';
import '../models/tag.dart';

// Provider for search query
final searchQueryProvider = StateProvider<String>((ref) => '');

// Provider for search active state
final isSearchActiveProvider = StateProvider<bool>((ref) => false);

// Provider for search results
final searchResultsProvider = Provider<List<Audiobook>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final isActive = ref.watch(isSearchActiveProvider);
  
  // If search is not active or query is empty, return empty list
  if (!isActive || query.trim().isEmpty) {
    return [];
  }
  
  // This will be implemented to get actual search results
  // For now, return empty list
  return [];
});

class SearchService {
  /// Performs fuzzy search on audiobooks
  static List<Audiobook> searchAudiobooks({
    required List<Audiobook> audiobooks,
    required String query,
    required Map<String, String> customTitles,
    required Map<String, Set<String>> audiobookTags,
    required List<Tag> allTags,
  }) {
    if (query.trim().isEmpty) {
      return audiobooks;
    }

    final searchQuery = query.toLowerCase().trim();
    final results = <Audiobook>[];

    for (final audiobook in audiobooks) {
      double score = 0.0;
      
      // Search in original title
      final originalTitle = audiobook.title.toLowerCase();
      score += _calculateMatchScore(originalTitle, searchQuery);
      
      // Search in custom title if exists
      final customTitle = customTitles[audiobook.id];
      if (customTitle != null) {
        score += _calculateMatchScore(customTitle.toLowerCase(), searchQuery) * 1.2; // Boost custom titles
      }
      
      // Search in author
      if (audiobook.author != null) {
        score += _calculateMatchScore(audiobook.author!.toLowerCase(), searchQuery) * 1.1;
      }
      
      // Search in tags
      final bookTags = audiobookTags[audiobook.id];
      if (bookTags != null) {
        for (final tagName in bookTags) {
          score += _calculateMatchScore(tagName.toLowerCase(), searchQuery) * 0.8;
        }
      }
      
      // Search in folder name (for series detection)
      final folderName = audiobook.id.split('/').last.toLowerCase();
      score += _calculateMatchScore(folderName, searchQuery) * 0.6;
      
      // If there's any match, add to results
      if (score > 0.1) {
        results.add(audiobook);
      }
    }

    // Sort by relevance score (highest first)
    results.sort((a, b) {
      final scoreA = _getTotalScore(a, searchQuery, customTitles, audiobookTags);
      final scoreB = _getTotalScore(b, searchQuery, customTitles, audiobookTags);
      return scoreB.compareTo(scoreA);
    });

    return results;
  }

  /// Calculate match score between text and query
  static double _calculateMatchScore(String text, String query) {
    if (text.isEmpty || query.isEmpty) return 0.0;
    
    // Exact match gets highest score
    if (text == query) return 100.0;
    
    // Contains query gets high score
    if (text.contains(query)) {
      // Bonus for match at beginning
      if (text.startsWith(query)) return 80.0;
      return 60.0;
    }
    
    // Fuzzy matching - check if all characters of query exist in text in order
    double fuzzyScore = _fuzzyMatch(text, query);
    
    // Word-based matching
    final textWords = text.split(' ');
    final queryWords = query.split(' ');
    double wordScore = 0.0;
    
    for (final queryWord in queryWords) {
      for (final textWord in textWords) {
        if (textWord.startsWith(queryWord)) {
          wordScore += 30.0 / queryWords.length;
        } else if (textWord.contains(queryWord)) {
          wordScore += 20.0 / queryWords.length;
        }
      }
    }
    
    return [fuzzyScore, wordScore].reduce((a, b) => a > b ? a : b);
  }

  /// Fuzzy matching algorithm
  static double _fuzzyMatch(String text, String query) {
    int textIndex = 0;
    int queryIndex = 0;
    int matches = 0;
    
    while (textIndex < text.length && queryIndex < query.length) {
      if (text[textIndex].toLowerCase() == query[queryIndex].toLowerCase()) {
        matches++;
        queryIndex++;
      }
      textIndex++;
    }
    
    if (queryIndex == query.length) {
      // All query characters found in order
      double matchRatio = matches / query.length;
      double lengthPenalty = 1.0 - (text.length - query.length).abs() / (text.length + query.length);
      return matchRatio * lengthPenalty * 40.0;
    }
    
    return 0.0;
  }

  /// Get total score for sorting
  static double _getTotalScore(
    Audiobook audiobook,
    String query,
    Map<String, String> customTitles,
    Map<String, Set<String>> audiobookTags,
  ) {
    double score = 0.0;
    final searchQuery = query.toLowerCase().trim();
    
    // Calculate all score components
    score += _calculateMatchScore(audiobook.title.toLowerCase(), searchQuery);
    
    final customTitle = customTitles[audiobook.id];
    if (customTitle != null) {
      score += _calculateMatchScore(customTitle.toLowerCase(), searchQuery) * 1.2;
    }
    
    if (audiobook.author != null) {
      score += _calculateMatchScore(audiobook.author!.toLowerCase(), searchQuery) * 1.1;
    }
    
    final bookTags = audiobookTags[audiobook.id];
    if (bookTags != null) {
      for (final tagName in bookTags) {
        score += _calculateMatchScore(tagName.toLowerCase(), searchQuery) * 0.8;
      }
    }
    
    return score;
  }
}

/// Search provider that combines all search functionality
class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(const SearchState());

  void updateQuery(String query) {
    state = state.copyWith(
      query: query,
      isActive: query.trim().isNotEmpty,
    );
  }

  void clearSearch() {
    state = const SearchState();
  }

  void toggleSearch() {
    state = state.copyWith(
      isActive: !state.isActive,
      query: state.isActive ? '' : state.query,
    );
  }
}

/// Search state class
class SearchState {
  final String query;
  final bool isActive;
  final List<String> searchHistory;

  const SearchState({
    this.query = '',
    this.isActive = false,
    this.searchHistory = const [],
  });

  SearchState copyWith({
    String? query,
    bool? isActive,
    List<String>? searchHistory,
  }) {
    return SearchState(
      query: query ?? this.query,
      isActive: isActive ?? this.isActive,
      searchHistory: searchHistory ?? this.searchHistory,
    );
  }
}

/// Provider for search notifier
final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier();
}); 