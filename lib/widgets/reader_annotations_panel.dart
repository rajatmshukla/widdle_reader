import 'package:flutter/material.dart';
import '../models/reader_annotation.dart';
import '../services/storage_service.dart';

/// Panel that displays highlights for an eBook (bookmarks removed).
class ReaderAnnotationsPanel extends StatefulWidget {
  final String ebookId;
  final Function(ReaderAnnotation)? onAnnotationTap;
  
  const ReaderAnnotationsPanel({
    super.key,
    required this.ebookId,
    this.onAnnotationTap,
  });

  @override
  State<ReaderAnnotationsPanel> createState() => _ReaderAnnotationsPanelState();
}

class _ReaderAnnotationsPanelState extends State<ReaderAnnotationsPanel> {
  final _storageService = StorageService();
  
  List<ReaderAnnotation> _highlights = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnotations();
  }

  Future<void> _loadAnnotations() async {
    setState(() => _isLoading = true);
    
    try {
      final annotationsData = await _storageService.loadReaderAnnotations(widget.ebookId);
      final annotations = annotationsData.map((data) {
        try {
          return ReaderAnnotation.fromJson(Map<String, dynamic>.from(data));
        } catch (e) {
          debugPrint('Error parsing individual annotation: $e');
          return null;
        }
      }).whereType<ReaderAnnotation>().toList();
      
      // Only keep highlights (has selected text that's not 'bookmark')
      setState(() {
        _highlights = annotations.where((a) => a.selectedText.isNotEmpty && a.selectedText != 'bookmark').toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading annotations: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAnnotation(ReaderAnnotation annotation) async {
    await _storageService.deleteReaderAnnotation(annotation.id);
    _loadAnnotations();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.format_color_fill, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Highlights (${_highlights.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildHighlightsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightsList() {
    if (_highlights.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _highlights.length,
      itemBuilder: (context, index) {
        final highlight = _highlights[index];
        return _buildHighlightTile(highlight);
      },
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.format_quote,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No highlights yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select text while reading to highlight it',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightTile(ReaderAnnotation highlight) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Dismissible(
      key: Key(highlight.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: colorScheme.error,
        child: Icon(Icons.delete, color: colorScheme.onError),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteAnnotation(highlight),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (highlight.color).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.format_quote,
              color: highlight.color,
            ),
          ),
          title: Text(
            '"${highlight.selectedText}"',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            _formatDate(highlight.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Delete highlight',
            onPressed: () => _deleteAnnotation(highlight),
          ),
          onTap: () => widget.onAnnotationTap?.call(highlight),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
