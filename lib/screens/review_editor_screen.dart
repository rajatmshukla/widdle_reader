import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import '../models/audiobook.dart';
import '../providers/audiobook_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/helpers.dart';

class ReviewEditorScreen extends StatefulWidget {
  final Audiobook audiobook;

  const ReviewEditorScreen({super.key, required this.audiobook});

  @override
  State<ReviewEditorScreen> createState() => _ReviewEditorScreenState();
}

class _ReviewEditorScreenState extends State<ReviewEditorScreen> with SingleTickerProviderStateMixin {
  late final QuillController _controller;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  double _rating = 0;
  bool _isSaving = false;
  
  // Animation for rating label
  late AnimationController _ratingAnimController;
  late Animation<double> _ratingScaleAnimation;

  @override
  void initState() {
    super.initState();
    _rating = widget.audiobook.rating ?? 0;
    
    // Initialize controller
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
    
    // Animation setup
    _ratingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ratingScaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _ratingAnimController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _ratingAnimController.dispose();
    super.dispose();
  }

  Future<void> _saveReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a rating to save (1-5 stars)'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

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
          SnackBar(
            content: const Text('Review saved successfully! ✨'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _getRatingLabel(double rating) {
    if (rating == 0) return 'Tap stars to rate! ✨';
    if (rating <= 1) return 'Not my cup of tea 😕';
    if (rating <= 2) return 'It was okay... 😐';
    if (rating <= 3) return 'Liked it! 🙂';
    if (rating <= 4) return 'Really good! 😀';
    return 'Absolute Favorite! 🤩';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = Provider.of<AudiobookProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final title = provider.getTitleForAudiobook(widget.audiobook);
    final isDark = theme.brightness == Brightness.dark;

    // Use app seed color for background gradient
    final seedColor = themeProvider.seedColor;
    final gradientColors = isDark
        ? [
            seedColor.withOpacity(0.3),
            colorScheme.surface,
            colorScheme.surfaceContainerLowest,
          ]
        : [
            seedColor.withOpacity(0.2),
            seedColor.withOpacity(0.05),
            colorScheme.surface,
          ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Write Review'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton(
              onPressed: _isSaving ? null : _saveReview,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20, 
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  controller: _editorScrollController,
                  slivers: [
                    // Glassmorphic Header Card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 20,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Hero(
                                        tag: 'cover_${widget.audiobook.id}',
                                        child: Container(
                                          width: 70, 
                                          height: 70,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.2),
                                                blurRadius: 8,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: buildCoverWidget(
                                            context, 
                                            widget.audiobook, 
                                            size: 70,
                                            customTitle: title,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (widget.audiobook.author != null)
                                              Text(
                                                widget.audiobook.author!,
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  // Rating Section
                                  ScaleTransition(
                                    scale: _ratingScaleAnimation,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                                      child: Text(
                                        _getRatingLabel(_rating),
                                        key: ValueKey(_rating),
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  RatingBar.builder(
                                    initialRating: _rating,
                                    minRating: 1,
                                    direction: Axis.horizontal,
                                    allowHalfRating: true,
                                    itemCount: 5,
                                    itemSize: 48,
                                    unratedColor: colorScheme.onSurface.withOpacity(0.2),
                                    glowColor: Colors.amber.withOpacity(0.6),
                                    glowRadius: 3,
                                    itemBuilder: (context, _) => const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                    ),
                                    onRatingUpdate: (rating) {
                                      setState(() => _rating = rating);
                                      _ratingAnimController.forward(from: 0.0);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Floating Toolbar
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(50), // Pill shape
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: QuillSimpleToolbar(
                                controller: _controller,
                                config: QuillSimpleToolbarConfig(
                                  multiRowsDisplay: false,
                                  showListNumbers: true,
                                  showListBullets: true,
                                  showQuote: true,
                                  showCodeBlock: true,
                                  showStrikeThrough: true,
                                  showLink: true,
                                  showInlineCode: true,
                                  showHeaderStyle: true,
                                  showFontFamily: true,
                                  showFontSize: true,
                                  showSearchButton: false, // Less useful on mobile
                                  showSubscript: true,
                                  showSuperscript: true,
                                  showUndo: true,
                                  showRedo: true,
                                  showClearFormat: true,
                                  showColorButton: true,
                                  showBackgroundColorButton: true,
                                  showIndent: true,
                                  buttonOptions: QuillSimpleToolbarButtonOptions(
                                    base: QuillToolbarBaseButtonOptions(
                                      iconTheme: QuillIconTheme(
                                        iconButtonSelectedData: IconButtonData(
                                          style: IconButton.styleFrom(
                                            backgroundColor: colorScheme.primary,
                                            foregroundColor: colorScheme.onPrimary,
                                            shape: const CircleBorder(),
                                          ),
                                        ),
                                        iconButtonUnselectedData: IconButtonData(
                                          style: IconButton.styleFrom(
                                            foregroundColor: colorScheme.onSurface,
                                            shape: const CircleBorder(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    // Expanded Editor Area
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: QuillEditor.basic(
                                controller: _controller,
                                focusNode: _editorFocusNode,
                                config: QuillEditorConfig(
                                  placeholder: 'Write your thoughts here... ✍️',
                                  padding: const EdgeInsets.all(24),
                                  autoFocus: false,
                                  expands: false, // Let it grow naturally inside scroll view
                                  scrollable: false, // Handled by CustomScrollView
                                  customStyles: DefaultStyles(
                                    placeHolder: DefaultTextBlockStyle(
                                      theme.textTheme.bodyLarge!.copyWith(
                                        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                                        fontSize: 18,
                                      ),
                                      const HorizontalSpacing(0, 0),
                                      const VerticalSpacing(0, 0),
                                      const VerticalSpacing(0, 0),
                                      null,
                                    ),
                                    paragraph: DefaultTextBlockStyle(
                                      theme.textTheme.bodyLarge!.copyWith(
                                        fontSize: 16, 
                                        height: 1.6,
                                        color: colorScheme.onSurface,
                                      ),
                                      const HorizontalSpacing(0, 0),
                                      const VerticalSpacing(8, 0),
                                      const VerticalSpacing(0, 0),
                                      null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
