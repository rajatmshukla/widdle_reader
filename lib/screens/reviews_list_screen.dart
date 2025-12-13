import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../providers/audiobook_provider.dart';
import '../utils/helpers.dart';
import 'review_editor_screen.dart';

class ReviewsListScreen extends StatelessWidget {
  const ReviewsListScreen({super.key});

  String _getSnippet(String jsonString) {
    try {
      final json = jsonDecode(jsonString);
      final doc = Document.fromJson(json);
      return doc.toPlainText().replaceAll('\n', ' ').trim();
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Using Provider instead of Riverpod
    final provider = Provider.of<AudiobookProvider>(context);
    final reviewedBooks = provider.reviewedBooks;
    
    if (reviewedBooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rate_review_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('No reviews yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Rate and review books to see them here.'),
          ],
        ),
      );
    }
    
    // Sort by review timestamp (newest first)
    final sortedBooks = List.of(reviewedBooks);
    sortedBooks.sort((a, b) {
      if (a.reviewTimestamp == null && b.reviewTimestamp == null) return 0;
      if (a.reviewTimestamp == null) return 1;
      if (b.reviewTimestamp == null) return -1;
      return b.reviewTimestamp!.compareTo(a.reviewTimestamp!);
    });
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: sortedBooks.length,
      itemBuilder: (context, index) {
        final book = sortedBooks[index];
        final snippet = (book.review != null && book.review!.isNotEmpty) ? _getSnippet(book.review!) : '';
        
        // Format date
        String dateString = '';
        if (book.reviewTimestamp != null) {
          final dt = book.reviewTimestamp!;
          const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          dateString = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
        }
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ReviewEditorScreen(audiobook: book)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover Art with Rating Overlay
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: buildCoverWidget(
                          context,
                          book,
                          size: 70,
                          customTitle: provider.getTitleForAudiobook(book),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                (book.rating ?? 0).toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                book.title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              book.author ?? 'Unknown Author',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (dateString.isNotEmpty)
                              Text(
                                dateString,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                        if (snippet.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
