import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audiobook.dart';
import '../services/cover_art_service.dart';
import '../providers/audiobook_provider.dart';
import 'dart:typed_data';

class CoverArtSelectionScreen extends StatefulWidget {
  final Audiobook audiobook;

  const CoverArtSelectionScreen({super.key, required this.audiobook});

  @override
  State<CoverArtSelectionScreen> createState() => _CoverArtSelectionScreenState();
}

class _CoverArtSelectionScreenState extends State<CoverArtSelectionScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final CoverArtService _coverArtService = CoverArtService();
  
  List<Map<String, String>> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.audiobook.title;
    _authorController.text = widget.audiobook.author ?? '';
    _performSearch();
  }

  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await _coverArtService.searchCovers(
        _titleController.text,
        _authorController.text,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
          if (results.isEmpty) {
            _error = "No covers found. Try adjusting your search.";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Error searching for covers: $e";
        });
      }
    }
  }

  Future<void> _selectCover(Map<String, String> result) async {
    setState(() => _isLoading = true);
    try {
      final largeUrl = result['largeUrl']!;
      final bytes = await _coverArtService.downloadAndSaveCover(largeUrl, widget.audiobook.id);
      
      if (bytes != null && mounted) {
        final provider = Provider.of<AudiobookProvider>(context, listen: false);
        await provider.updateAudiobookCover(widget.audiobook.id, bytes);
        if (mounted) Navigator.pop(context);
      } else {
        setState(() {
          _isLoading = false;
          _error = "Failed to download cover.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Extract message from Exception if possible
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Cover Art"),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Filters
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: "Book Title",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.book),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _authorController,
                  decoration: const InputDecoration(
                    labelText: "Author",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _performSearch,
                    icon: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search),
                    label: const Text("Search Open Library"),
                  ),
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                ))
              : _isLoading && _results.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return InkWell(
                        onTap: () => _selectCover(result),
                        borderRadius: BorderRadius.circular(12),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          elevation: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Image.network(
                                  result['thumbUrl']!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(child: CircularProgressIndicator());
                                  },
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 48),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      result['title']!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                    Text(
                                      result['author']!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
