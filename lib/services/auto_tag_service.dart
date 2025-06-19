import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tag.dart';
import '../providers/tag_provider.dart';
import 'metadata_service.dart';

class AutoTagService {
  final WidgetRef ref;
  final MetadataService _metadataService = MetadataService();

  AutoTagService(this.ref);

  /// Creates and assigns auto-tags for multiple audiobooks
  Future<AutoTagResult> createAutoTagsForAudiobooks({
    required List<String> audiobookPaths,
    required String rootPath,
    bool createTags = true,
    bool assignTags = true,
  }) async {
    final result = AutoTagResult();
    
    try {
      debugPrint("Starting auto-tag creation for ${audiobookPaths.length} audiobooks");
      debugPrint("Root path: $rootPath");
      debugPrint("Audiobook paths: ${audiobookPaths.map((p) => p.split('/').last).join(', ')}");
      
      // Get suggested tags from metadata service
      final suggestedTags = _metadataService.suggestTagNames(audiobookPaths, rootPath);
      
      debugPrint("Suggested tags: $suggestedTags");
      
      if (suggestedTags.isEmpty) {
        debugPrint("No suitable tags found for auto-creation");
        debugPrint("Checking individual books for potential tags:");
        for (final path in audiobookPaths) {
          final potentialTags = _metadataService.extractPotentialTags(path, rootPath);
          debugPrint("  ${path.split('/').last}: $potentialTags");
        }
        return result;
      }
      
      debugPrint("Found ${suggestedTags.length} potential tags: $suggestedTags");
      
      // Get existing tags to avoid duplicates
      final tagNotifier = ref.read(tagProvider.notifier);
      final audiobookTagsNotifier = ref.read(audiobookTagsProvider.notifier);
      
      // Create tags that don't exist yet
      if (createTags) {
        debugPrint("Creating tags...");
        for (final tagName in suggestedTags) {
          try {
            await tagNotifier.createTag(tagName);
            result.createdTags.add(tagName);
            debugPrint("Created tag: '$tagName'");
          } catch (e) {
            if (e.toString().contains('already exists')) {
              debugPrint("Tag '$tagName' already exists, skipping creation");
              result.existingTags.add(tagName);
            } else {
              debugPrint("Error creating tag '$tagName': $e");
              result.failedTags.add(tagName);
            }
          }
        }
      }
      
      // Assign tags to audiobooks
      if (assignTags) {
        debugPrint("Assigning tags to audiobooks...");
        final Map<String, int> assignmentCounts = {};
        
        for (final audiobookPath in audiobookPaths) {
          final audiobookId = audiobookPath;
          final potentialTags = _metadataService.extractPotentialTags(audiobookPath, rootPath);
          
          debugPrint("Processing audiobook: ${audiobookPath.split('/').last}");
          debugPrint("  Potential tags: $potentialTags");
          debugPrint("  Suggested tags: $suggestedTags");
          
          for (final tagName in potentialTags) {
            if (suggestedTags.contains(tagName)) {
              try {
                await audiobookTagsNotifier.addTagToAudiobook(audiobookId, tagName);
                
                assignmentCounts[tagName] = (assignmentCounts[tagName] ?? 0) + 1;
                result.tagAssignments[tagName] = result.tagAssignments[tagName] ?? <String>[];
                result.tagAssignments[tagName]!.add(audiobookPath);
                
                debugPrint("Assigned tag '$tagName' to audiobook: ${audiobookPath.split('/').last}");
              } catch (e) {
                debugPrint("Error assigning tag '$tagName' to audiobook '$audiobookId': $e");
              }
            }
          }
        }
        
        // Update tag usage timestamps
        for (final tagName in assignmentCounts.keys) {
          try {
            await tagNotifier.updateTagUsage(tagName);
          } catch (e) {
            debugPrint("Error updating tag usage for '$tagName': $e");
          }
        }
        
        result.totalAssignments = assignmentCounts.values.fold(0, (sum, count) => sum + count);
      }
      
      debugPrint("Auto-tag creation completed:");
      debugPrint("  Created tags: ${result.createdTags.length}");
      debugPrint("  Existing tags: ${result.existingTags.length}");
      debugPrint("  Failed tags: ${result.failedTags.length}");
      debugPrint("  Total assignments: ${result.totalAssignments}");
      
    } catch (e) {
      debugPrint("Error in auto-tag creation process: $e");
      result.error = e.toString();
    }
    
    return result;
  }

  /// Creates and assigns auto-tags for a single audiobook
  Future<AutoTagResult> createAutoTagsForSingleAudiobook({
    required String audiobookPath,
    required String rootPath,
    bool createTags = true,
    bool assignTags = true,
  }) async {
    return createAutoTagsForAudiobooks(
      audiobookPaths: [audiobookPath],
      rootPath: rootPath,
      createTags: createTags,
      assignTags: assignTags,
    );
  }

  /// Previews what tags would be created without actually creating them
  Future<AutoTagPreview> previewAutoTags({
    required List<String> audiobookPaths,
    required String rootPath,
  }) async {
    final preview = AutoTagPreview();
    
    try {
      // Get suggested tags
      final suggestedTags = _metadataService.suggestTagNames(audiobookPaths, rootPath);
      
      // Get existing tags
      final existingTagNames = <String>{};
      try {
        final tagState = ref.read(tagProvider);
        tagState.whenData((tags) {
          existingTagNames.addAll(tags.map((tag) => tag.name));
        });
      } catch (e) {
        debugPrint("Could not load existing tags for preview: $e");
      }
      
      // Categorize tags
      for (final tagName in suggestedTags) {
        if (existingTagNames.contains(tagName)) {
          preview.existingTags.add(tagName);
        } else {
          preview.newTags.add(tagName);
        }
      }
      
      // Calculate assignments
      for (final audiobookPath in audiobookPaths) {
        final potentialTags = _metadataService.extractPotentialTags(audiobookPath, rootPath);
        final audiobookName = audiobookPath.split('/').last;
        
        for (final tagName in potentialTags) {
          if (suggestedTags.contains(tagName)) {
            preview.tagAssignments[tagName] = preview.tagAssignments[tagName] ?? <String>[];
            preview.tagAssignments[tagName]!.add(audiobookName);
          }
        }
      }
      
    } catch (e) {
      debugPrint("Error creating auto-tag preview: $e");
      preview.error = e.toString();
    }
    
    return preview;
  }
}

/// Result of auto-tag creation process
class AutoTagResult {
  final List<String> createdTags = [];
  final List<String> existingTags = [];
  final List<String> failedTags = [];
  final Map<String, List<String>> tagAssignments = {};
  int totalAssignments = 0;
  String? error;

  bool get hasSuccess => createdTags.isNotEmpty || totalAssignments > 0;
  bool get hasError => error != null || failedTags.isNotEmpty;

  String get summary {
    final parts = <String>[];
    
    if (createdTags.isNotEmpty) {
      parts.add("Created ${createdTags.length} new tag${createdTags.length == 1 ? '' : 's'}");
    }
    
    if (existingTags.isNotEmpty) {
      parts.add("Used ${existingTags.length} existing tag${existingTags.length == 1 ? '' : 's'}");
    }
    
    if (totalAssignments > 0) {
      parts.add("Made $totalAssignments tag assignment${totalAssignments == 1 ? '' : 's'}");
    }
    
    if (failedTags.isNotEmpty) {
      parts.add("Failed to create ${failedTags.length} tag${failedTags.length == 1 ? '' : 's'}");
    }
    
    return parts.isNotEmpty ? parts.join(', ') : 'No changes made';
  }
}

/// Preview of what auto-tag creation would do
class AutoTagPreview {
  final List<String> newTags = [];
  final List<String> existingTags = [];
  final Map<String, List<String>> tagAssignments = {};
  String? error;

  bool get isEmpty => newTags.isEmpty && existingTags.isEmpty;
  bool get hasError => error != null;

  int get totalNewTags => newTags.length;
  int get totalAssignments => tagAssignments.values.fold(0, (sum, list) => sum + list.length);

  String get summary {
    if (hasError) return "Error: $error";
    if (isEmpty) return "No tags would be created";
    
    final parts = <String>[];
    
    if (newTags.isNotEmpty) {
      parts.add("${newTags.length} new tag${newTags.length == 1 ? '' : 's'}");
    }
    
    if (existingTags.isNotEmpty) {
      parts.add("${existingTags.length} existing tag${existingTags.length == 1 ? '' : 's'}");
    }
    
    if (totalAssignments > 0) {
      parts.add("$totalAssignments assignment${totalAssignments == 1 ? '' : 's'}");
    }
    
    return "Would create/use: ${parts.join(', ')}";
  }
} 