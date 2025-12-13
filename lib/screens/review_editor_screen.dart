import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import '../models/audiobook.dart';
import '../providers/audiobook_provider.dart';

class ReviewEditorScreen extends StatefulWidget {
  final Audiobook audiobook;

  const ReviewEditorScreen({super.key, required this.audiobook});

  @override
  State<ReviewEditorScreen> createState() => _ReviewEditorScreenState();
}

class _ReviewEditorScreenState extends State<ReviewEditorScreen> {
  late final QuillController _controller;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  double _rating = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.audiobook.rating ?? 0;
    
    // Initialize controller with existing content or empty
    if (widget.audiobook.review != null && widget.audiobook.review!.isNotEmpty) {
      try {
        final json = jsonDecode(widget.audiobook.review!);
        _controller = QuillController(
          document: Document.fromJson(json),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (e) {
        debugPrint("Error parsing existing review: $e");
        _controller = QuillController.basic();
      }
    } else {
      _controller = QuillController.basic();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  Future<void> _saveReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final reviewContent = jsonEncode(_controller.document.toDelta().toJson());
      
      final provider = Provider.of<AudiobookProvider>(context, listen: false);
      await provider.saveReview(
        widget.audiobook.id,
        _rating,
        reviewContent,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving review: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('Review ${widget.audiobook.title}'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.tonal(
              onPressed: _isSaving ? null : _saveReview,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                controller: _editorScrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Column(
                        children: [
                          // Rating Card
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _rating == 0 ? 'How was it?' : 'Your Rating',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                RatingBar.builder(
                                  initialRating: _rating,
                                  minRating: 1,
                                  direction: Axis.horizontal,
                                  allowHalfRating: true,
                                  itemCount: 5,
                                  itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  itemBuilder: (context, _) => const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                  ),
                                  onRatingUpdate: (rating) {
                                    setState(() {
                                      _rating = rating;
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_rating.toStringAsFixed(1)} / 5.0',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  
                  // Editor Section
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer, // M3 container color
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Toolbar attached to top of editor
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(24),
                                topRight: Radius.circular(24),
                              ),
                              border: Border(
                                bottom: BorderSide(color: colorScheme.outlineVariant),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: QuillSimpleToolbar(
                              controller: _controller,
                              config: QuillSimpleToolbarConfig(
                                showListNumbers: true,
                                showListBullets: true,
                                showQuote: true,
                                showCodeBlock: false,
                                showStrikeThrough: true,
                                showLink: false,
                                showInlineCode: false,
                                showHeaderStyle: false,
                                showFontFamily: false,
                                showFontSize: false,
                                showSearchButton: false,
                                showSubscript: false,
                                showSuperscript: false,
                                buttonOptions: QuillSimpleToolbarButtonOptions(
                                  base: QuillToolbarBaseButtonOptions(
                                    iconTheme: QuillIconTheme(
                                      iconButtonSelectedData: IconButtonData(
                                        style: IconButton.styleFrom(
                                          backgroundColor: colorScheme.primaryContainer,
                                          foregroundColor: colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                      iconButtonUnselectedData: IconButtonData(
                                        style: IconButton.styleFrom(
                                          foregroundColor: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          // Editor Content
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: QuillEditor.basic(
                                controller: _controller,
                                focusNode: _editorFocusNode,
                                config: QuillEditorConfig(
                                  placeholder: 'Write your review here...',
                                  padding: const EdgeInsets.only(bottom: 64), // Space for fab or scrolling
                                  scrollable: true,
                                  autoFocus: false,
                                  expands: false,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
