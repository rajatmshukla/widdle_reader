import 'dart:async';
import '../app_globals.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:marquee/marquee.dart';
import '../models/audiobook.dart';
import '../models/ebook.dart';
import '../models/reader_annotation.dart';
import '../services/storage_service.dart';
import '../services/native_scanner.dart';
import '../widgets/reader_mini_player.dart';
import '../widgets/reader_annotations_panel.dart';

/// Text reader content widget that displays PDF or EPUB files.
/// Used within the player screen's PageView for Read mode.
class TextReaderContent extends StatefulWidget {
  final Audiobook? audiobook;
  final VoidCallback? onBackToPlayer;

  const TextReaderContent({
    super.key,
    this.audiobook,
    this.onBackToPlayer,
  });

  @override
  State<TextReaderContent> createState() => _TextReaderContentState();
}

class _TextReaderContentState extends State<TextReaderContent>
    with WidgetsBindingObserver {
  final _storageService = StorageService();

  List<String> _ebookPaths = [];
  EBook? _currentEbook;
  bool _isLoading = true;
  String? _errorMessage;
  int _currentPage = 0;
  
  // PDF controller
  PdfViewerController? _pdfController;
  
  // EPUB controller
  EpubController? _epubController;

  // Reader settings
  bool _isDarkMode = false;
  int _fontSize = 18; // EPUB font size in pixels (18px default)
  bool _showNavHint = false;
  bool _showMarquee = false;
  Timer? _marqueeTimer;
  
  // SAF Bridge: stores local file paths for content:// URIs
  final Map<String, String> _safBridgeCache = {};
  
  // Race condition guard: tracks current loading operation
  int _loadingTag = 0;
  
  // EPUB Chapters
  List<EpubChapter>? _epubChapters;
  
  // Selection state for highlighting (EPUB)
  String? _selectedText;
  String? _selectedCfi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _epubController = EpubController();
    _pdfController = PdfViewerController();
    _scanForEbooks();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save position when app is backgrounded or paused
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      _savePosition();
      debugPrint('📖 Reader: Saved position on lifecycle $state');
    }
  }


  @override
  void didUpdateWidget(TextReaderContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audiobook?.id != widget.audiobook?.id) {
      _scanForEbooks();
    }
  }

  Future<void> _scanForEbooks() async {
    if (widget.audiobook == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No audiobook loaded';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final paths = await _storageService.findEbooksInFolder(widget.audiobook!.id);
      
      if (paths.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No eBook files found in this audiobook folder.\n\nPlace PDF or EPUB files in the same folder as your audiobook.';
          _ebookPaths = [];
        });
        return;
      }

      setState(() {
        _ebookPaths = paths;
      });

      // Auto-load first ebook
      await _loadEbook(paths.first);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error scanning for ebooks: $e';
      });
    }
  }

  Future<void> _loadEbook(String path) async {
    // Race condition guard: increment tag and check if still current
    final thisLoadTag = ++_loadingTag;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // SAF Bridge: extract content:// URI to local temp file
      String localPath = path;
      if (Platform.isAndroid && path.startsWith('content://')) {
        localPath = await _prepareFileForViewer(path);
      }
      
      // Check if this load is still the current one
      if (thisLoadTag != _loadingTag) {
        debugPrint('📖 Load cancelled (superseded by newer load)');
        return;
      }
      
      final ebook = EBook.fromFile(path, audiobookId: widget.audiobook?.id);
      // Store the local path for viewer use
      _safBridgeCache[path] = localPath;
      
      // Load saved position
      final savedPosition = await _storageService.loadReaderPosition(ebook.id);
      if (savedPosition != null) {
        ebook.lastPage = savedPosition['page'] as int? ?? 0;
        ebook.lastCfi = savedPosition['cfi'] as String?;
      }

      if (ebook.type == EBookType.pdf) {
        _pdfController = PdfViewerController();
      }
      
      // Final check before updating state
      if (thisLoadTag != _loadingTag) return;

      setState(() {
        _currentEbook = ebook;
        _currentPage = ebook.lastPage;
        _isLoading = false;
        // Show hint if this is the first time loading an ebook in this session
        _showNavHint = true;
        
        // Setup marquee to scroll once
        _showMarquee = true;
        _marqueeTimer?.cancel();
        _marqueeTimer = Timer(const Duration(seconds: 12), () {
          if (mounted) setState(() => _showMarquee = false);
        });
      });

      // Hide hint after 4 seconds
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showNavHint = false);
      });

      // Jump to saved position after build (PDF only)
      if (ebook.type == EBookType.pdf && ebook.lastPage > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pdfController?.goToPage(pageNumber: ebook.lastPage + 1);
        });
      }


    } catch (e) {
      if (thisLoadTag != _loadingTag) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading ebook: $e';
      });
    }
  }


  /// Prepares a SAF content:// URI by copying to local temp storage.
  /// Returns the local file path that can be used with File().
  Future<String> _prepareFileForViewer(String safUri) async {
    // Check cache first
    if (_safBridgeCache.containsKey(safUri)) {
      final cached = _safBridgeCache[safUri]!;
      if (await File(cached).exists()) {
        return cached;
      }
    }
    
    // Read bytes from SAF URI
    final bytes = await NativeScanner.readBytes(safUri);
    if (bytes == null) {
      throw Exception('Could not read file from SAF URI');
    }
    
    // Get temp directory and create file
    final tempDir = await getTemporaryDirectory();
    final fileName = safUri.split('%2F').last.split('/').last;
    final localFile = File('${tempDir.path}/reader_cache/$fileName');
    
    // Ensure directory exists
    await localFile.parent.create(recursive: true);
    
    // Write bytes
    await localFile.writeAsBytes(bytes);
    
    debugPrint('📖 SAF Bridge: Extracted $fileName to ${localFile.path}');
    return localFile.path;
  }

  /// Decodes and cleans up filename from URI
  String _getDisplayName(String path) {
    try {
      if (path.startsWith('content://')) {
        // Extract filename from SAF URI
        String name = Uri.decodeFull(path).split('/').last;
        if (name.contains(':')) {
          name = name.split(':').last;
        }
        return name;
      }
      return path.split('/').last.split('\\').last;
    } catch (e) {
      return path.split('/').last;
    }
  }


  Future<void> _savePosition() async {
    if (_currentEbook == null) return;
    
    double? zoom;
    double? offsetX;
    double? offsetY;
    
    if (_currentEbook?.type == EBookType.pdf && _pdfController != null) {
      try {
        // Just page persistence for now as zoom/offset API is version-dependent
        debugPrint('📖 Reader: Capturing PDF state (page: $_currentPage)');
      } catch (e) {
        debugPrint('Error getting PDF controller state: $e');
      }
    }

    
    await _storageService.saveReaderPosition(
      _currentEbook!.id,
      page: _currentPage,
      cfi: _currentEbook!.lastCfi,
      zoom: zoom,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }


  /// Safe SnackBar display using global root key
  Future<void> _showSnackBar(String message) async {
    if (!mounted) return;
    
    // Small delay to allow keyboard animations to finish if needed
    await Future.delayed(const Duration(milliseconds: 300));
    
    try {
      rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error showing snackbar: $e');
    }
  }

  void _prevPage() {
    if (_currentEbook == null) return;
    try {
      if (_currentEbook!.type == EBookType.pdf) {
        if (_currentPage > 0) {
          _pdfController?.goToPage(pageNumber: _currentPage);
        }
      } else {
        _epubController?.prev();
      }
    } catch (e) {
      debugPrint('Navigation error (prev): $e');
    }
  }

  void _nextPage() {
    if (_currentEbook == null) return;
    try {
      if (_currentEbook!.type == EBookType.pdf) {
        _pdfController?.goToPage(pageNumber: _currentPage + 2);
      } else {
        _epubController?.next();
      }
    } catch (e) {
      debugPrint('Navigation error (next): $e');
    }
  }

  Widget _buildNavigationControls() {
    return Positioned.fill(
      child: Row(
        children: [
          // Left tap zone (20%) - for previous page
          Expanded(
            flex: 1,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _prevPage,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Center area (60%) - IgnorePointer allows gestures to pass through for pinch-zoom
          Expanded(
            flex: 3,
            child: IgnorePointer(
              child: Container(color: Colors.transparent),
            ),
          ),
          // Right tap zone (20%) - for next page
          Expanded(
            flex: 1,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _nextPage,
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the annotations panel (bookmarks & highlights)
  void _showAnnotationsPanel() {
    if (_currentEbook == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ReaderAnnotationsPanel(
        ebookId: _currentEbook!.id,
        onAnnotationTap: (annotation) {
          Navigator.pop(sheetContext);
          _goToAnnotation(annotation);
        },
      ),
    );
  }

    /// Navigates to a specific annotation location
  void _goToAnnotation(ReaderAnnotation annotation) {
    if (_currentEbook == null) return;
    
    try {
      if (_currentEbook!.type == EBookType.pdf && annotation.pageNumber != null) {
        _pdfController?.goToPage(pageNumber: annotation.pageNumber! + 1);
        setState(() {
          _currentPage = annotation.pageNumber!;
        });
      } else if (_currentEbook!.type == EBookType.epub && annotation.cfi != null) {
        _epubController?.display(cfi: annotation.cfi!);
      }
    } catch (e) {
      debugPrint('Error navigating to annotation: $e');
      _showSnackBar('Error navigating to annotation');
    }
  }
  
  /// Loads and restores highlights for the current book (EPUB only for now)
  Future<void> _restoreHighlights() async {
    if (_currentEbook == null) return;
    
    try {
      final annotationsData = await _storageService.loadReaderAnnotations(_currentEbook!.id);
      final annotations = annotationsData
          .map((data) => ReaderAnnotation.fromJson(Map<String, dynamic>.from(data)))
          .where((a) => a.selectedText.isNotEmpty && a.selectedText != 'bookmark')
          .toList();
          
      if (_currentEbook!.type == EBookType.epub && _epubController != null) {
        for (final annotation in annotations) {
          if (annotation.cfi != null) {
            _epubController!.addHighlight(
              cfi: annotation.cfi!,
              color: Color(annotation.colorHex),
            );
          }
        }
        debugPrint('📖 Reader: Restored ${annotations.length} highlights in EPUB');
      }
    } catch (e) {
      debugPrint('Error restoring highlights: $e');
    }
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _marqueeTimer?.cancel();
    _savePosition();
    _cleanupReaderCache();
    super.dispose();
  }
  
  /// Cleans up temporary cached files from SAF bridge
  Future<void> _cleanupReaderCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory('${tempDir.path}/reader_cache');
      if (await cacheDir.exists()) {
        // Delete files older than 24 hours to avoid cleaning files in use
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        await for (final entity in cacheDir.list()) {
          if (entity is File) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              debugPrint('📖 Cleaned up old cache file: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning reader cache: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark || _isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Reader toolbar
            _buildToolbar(colorScheme, isDark),
            
            // Main content area
            Expanded(
              child: _buildContent(colorScheme, isDark),
            ),
            
            // Mini player at bottom
            ReaderMiniPlayer(
              onTap: widget.onBackToPlayer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme, bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[100],
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: Icon(Icons.arrow_back, color: textColor),
            onPressed: widget.onBackToPlayer,
            tooltip: 'Back to Player',
          ),
          
          // Title with Marquee if long (scrolls once)
          Expanded(
            child: SizedBox(
              height: 32,
              child: _currentEbook != null && 
                     _getDisplayName(_currentEbook!.filePath).length > 25 &&
                     _showMarquee
                  ? Marquee(
                      key: ValueKey('marquee-${_currentEbook!.filePath}'),
                      text: _getDisplayName(_currentEbook!.filePath),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                      scrollAxis: Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      blankSpace: 50.0,
                      velocity: 30.0,
                      pauseAfterRound: const Duration(seconds: 2),
                      accelerationDuration: const Duration(seconds: 1),
                      accelerationCurve: Curves.linear,
                      decelerationDuration: const Duration(milliseconds: 500),
                      decelerationCurve: Curves.easeOut,
                    )
                  : Center(
                      child: Text(
                        _currentEbook != null 
                            ? _getDisplayName(_currentEbook!.filePath)
                            : 'Reader',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
          
          // Font size controls for EPUB
          if (_currentEbook?.type == EBookType.epub) ...[
            IconButton(
              icon: Icon(Icons.text_decrease, color: textColor, size: 20),
              onPressed: () {
                final newSize = (_fontSize - 2).clamp(12, 36);
                setState(() => _fontSize = newSize);
                _epubController?.setFontSize(fontSize: newSize.toDouble());
                debugPrint('📖 Font size decreased to: $newSize');
              },
              tooltip: 'Smaller text ($_fontSize)',
            ),
            IconButton(
              icon: Icon(Icons.text_increase, color: textColor, size: 20),
              onPressed: () {
                final newSize = (_fontSize + 2).clamp(12, 36);
                setState(() => _fontSize = newSize);
                _epubController?.setFontSize(fontSize: newSize.toDouble());
                debugPrint('📖 Font size increased to: $newSize');
              },
              tooltip: 'Larger text ($_fontSize)',
            ),
          ],
          
          // View highlights (EPUB only)
          if (_currentEbook?.type == EBookType.epub)
            IconButton(
              icon: Icon(Icons.format_color_fill, color: textColor),
              onPressed: _currentEbook != null ? _showAnnotationsPanel : null,
              tooltip: 'View Highlights',
            ),
          
          // Highlight selected text (appears when text is selected)
          if (_selectedText != null && _currentEbook?.type == EBookType.epub)
            PopupMenuButton<int>(
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.yellow.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.border_color, color: textColor, size: 20),
              ),
              tooltip: 'Highlight selected text',
              onSelected: (colorHex) {
                _applyHighlight(colorHex);
              },
              itemBuilder: (context) => HighlightColors.all.map((colorHex) {
                return PopupMenuItem<int>(
                  value: colorHex,
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(colorHex),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_getColorName(colorHex)),
                    ],
                  ),
                );
              }).toList(),
            ),

          // EPUB Chapter button
          if (_currentEbook?.type == EBookType.epub && _epubChapters != null && _epubChapters!.isNotEmpty)
            IconButton(
              icon: Icon(Icons.list, color: textColor),
              onPressed: _showChaptersDialog,
              tooltip: 'Chapters',
            ),
          
          // File picker if multiple ebooks
          if (_ebookPaths.length > 1)
            PopupMenuButton<String>(
              icon: Icon(Icons.menu_book, color: textColor),
              tooltip: 'Select file',
              onSelected: _loadEbook,
              itemBuilder: (context) => _ebookPaths.map((path) {
                final name = _getDisplayName(path);
                final isSelected = path == _currentEbook?.filePath;
                return PopupMenuItem(
                  value: path,
                  child: Row(
                    children: [
                      if (isSelected)
                        Icon(Icons.check, size: 18, color: colorScheme.primary),
                      if (isSelected) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme, bool isDark) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Searching for eBook files...',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 64,
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _scanForEbooks,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentEbook == null) {
      return const Center(child: Text('No ebook loaded'));
    }

    // Render based on type
    if (_currentEbook!.type == EBookType.pdf) {
      return _buildPdfViewer(isDark);
    } else {
      return _buildEpubViewer(isDark);
    }
  }

  Widget _buildPdfViewer(bool isDark) {
    // Use SAF bridge local path if available
    final localPath = _safBridgeCache[_currentEbook!.filePath] ?? _currentEbook!.filePath;
    
    return Stack(
      children: [
        PdfViewer.file(
          localPath,
          controller: _pdfController,
          params: PdfViewerParams(
            backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
            pageOverlaysBuilder: (context, pageRect, page) {
              // Update current page
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _currentPage != page.pageNumber - 1) {
                  setState(() {
                    _currentPage = page.pageNumber - 1;
                  });
                }
              });
              return [];
            },
          ),
        ),
        _buildNavigationControls(),
      ],
    );
  }


  Widget _buildEpubViewer(bool isDark) {
    // Ensure controller is initialized
    _epubController ??= EpubController();
    
    // Use SAF bridge local path if available
    final localPath = _safBridgeCache[_currentEbook!.filePath] ?? _currentEbook!.filePath;
    
    return Stack(
      children: [
        EpubViewer(
          epubSource: EpubSource.fromFile(File(localPath)),
          epubController: _epubController!,
          displaySettings: EpubDisplaySettings(
            flow: EpubFlow.paginated,
            snap: true,
            fontSize: _fontSize,
          ),
          onChaptersLoaded: (chapters) {
            debugPrint('EPUB Chapters loaded: ${chapters.length}');
            if (mounted) {
              setState(() {
                _epubChapters = chapters;
              });
            }
          },
          onEpubLoaded: () {
            debugPrint('EPUB loaded successfully');
            // Restore saved position after EPUB is fully loaded
            if (_currentEbook?.lastCfi != null && _currentEbook!.lastCfi!.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  _epubController?.display(cfi: _currentEbook!.lastCfi!);
                  debugPrint('EPUB position restored to: ${_currentEbook!.lastCfi}');
                } catch (e) {
                  debugPrint('EPUB position restoration error: $e');
                }
              });
            }
            
            // Restore highlights
            _restoreHighlights();
          },
          onRelocated: (value) {
            if (_currentEbook == null) return;
            // Save position - value is EpubLocation with startCfi/endCfi
            final cfi = value.startCfi ?? '';
            debugPrint('EPUB relocated: $cfi');
            _currentEbook!.lastCfi = cfi;
            
            // Non-blocking save
            _storageService.saveReaderPosition(
              _currentEbook!.id,
              cfi: cfi,
            ).catchError((e) => debugPrint('Error saving EPUB position: $e'));
          },
          onTextSelected: (selection) {
            if (selection.selectedText.isEmpty) {
              // Clear selection if empty
              if (mounted) setState(() {
                _selectedText = null;
                _selectedCfi = null;
              });
              return;
            }
            debugPrint('Text selected: ${selection.selectedText}');
            // Store selection - user can then tap highlight button in toolbar
            if (mounted) setState(() {
              _selectedText = selection.selectedText;
              _selectedCfi = selection.selectionCfi;
            });
          },
        ),
        
        _buildNavigationControls(),
        
        // Navigation Hint Overlay
        if (_showNavHint)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showNavHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.swipe, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Swipe edges or tap sides to turn pages',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }


  /// Shows a dialog with the EPUB chapter list for navigation
  void _showChaptersDialog() {
    if (_epubChapters == null || _epubChapters!.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chapters'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _epubChapters!.length,
            separatorBuilder: (_, index) => const Divider(),
            itemBuilder: (_, index) {
              final chapter = _epubChapters![index];
              return ListTile(
                title: Text(chapter.title ?? 'Chapter ${index + 1}'),
                onTap: () {
                  Navigator.pop(dialogContext);
                  if (chapter.href != null) {
                    _epubController?.display(cfi: chapter.href!);
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Applies highlight to currently selected text with the given color
  void _applyHighlight(int colorHex) {
    if (_currentEbook == null || _selectedText == null) return;
    
    _saveHighlight(
      ebookId: _currentEbook!.id,
      cfi: _selectedCfi,
      text: _selectedText!,
      colorHex: colorHex,
    );
    
    // Clear selection after applying
    setState(() {
      _selectedText = null;
      _selectedCfi = null;
    });
  }
  
  /// Gets a human-readable name for a highlight color
  String _getColorName(int colorHex) {
    switch (colorHex) {
      case 0xFFFFEB3B: return 'Yellow';
      case 0xFF4CAF50: return 'Green';
      case 0xFF2196F3: return 'Blue';
      case 0xFFFF9800: return 'Orange';
      case 0xFFE91E63: return 'Pink';
      default: return 'Color';
    }
  }
  
  /// Saves a highlight asynchronously (called after dialog closes)
  Future<void> _saveHighlight({
    required String ebookId,
    String? cfi,
    required String text,
    required int colorHex,
  }) async {
    try {
      final annotation = ReaderAnnotation.create(
        ebookId: ebookId,
        cfi: cfi,
        selectedText: text,
        colorHex: colorHex,
      );
      
      await _storageService.saveReaderAnnotation(annotation.toJson());
      
      // Apply visual highlight immediately for EPUB
      if (_currentEbook?.type == EBookType.epub && _epubController != null && cfi != null) {
        _epubController!.addHighlight(
          cfi: cfi,
          color: Color(colorHex),
        );
      }
      
      _showSnackBar('Highlight saved');
    } catch (e) {
      debugPrint('Error saving highlight: $e');
      _showSnackBar('Error saving highlight: $e');
    }
  }

}
