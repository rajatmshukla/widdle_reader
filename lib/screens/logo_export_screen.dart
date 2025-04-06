import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:widdle_reader/widgets/app_logo.dart';
import 'package:provider/provider.dart';
import 'package:widdle_reader/providers/theme_provider.dart';

class LogoExportScreen extends StatefulWidget {
  const LogoExportScreen({super.key});

  @override
  State<LogoExportScreen> createState() => _LogoExportScreenState();
}

class _LogoExportScreenState extends State<LogoExportScreen> {
  final GlobalKey _logoKey = GlobalKey();
  bool _exporting = false;
  String? _exportPath;
  double _logoSize = 512; // Size for the logo (512×512 is good for app icons)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export App Logo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo preview with RepaintBoundary to capture it
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: RepaintBoundary(
                key: _logoKey,
                child: Container(
                  width: _logoSize,
                  height: _logoSize,
                  color: Colors.transparent, // Transparent background
                  child: Center(
                    child: AppLogo(
                      size: _logoSize * 0.8, // Slightly smaller to add padding
                      showTitle: false,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Size selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Logo Size: '),
                DropdownButton<double>(
                  value: _logoSize,
                  items:
                      [128.0, 256.0, 512.0, 1024.0].map((size) {
                        return DropdownMenuItem<double>(
                          value: size,
                          child: Text('${size.toInt()}×${size.toInt()}'),
                        );
                      }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _logoSize = value;
                      });
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Export button and status
            _exporting
                ? const CircularProgressIndicator()
                : ElevatedButton(
                  onPressed: _captureAndSaveLogo,
                  child: const Text('Export Logo Image'),
                ),

            const SizedBox(height: 16),

            // Show export path if available
            if (_exportPath != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Logo exported to:'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _exportPath!,
                        style: const TextStyle(fontFamily: 'monospace'),
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

  Future<void> _captureAndSaveLogo() async {
    try {
      setState(() {
        _exporting = true;
        _exportPath = null;
      });

      // Delay to ensure UI is built
      await Future.delayed(const Duration(milliseconds: 500));

      // Capture logo as image
      final RenderRepaintBoundary boundary =
          _logoKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        throw Exception('Failed to convert image to bytes');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // Save to file
      final directory = await getApplicationDocumentsDirectory();
      final String fileName =
          'app_logo_${DateTime.now().millisecondsSinceEpoch}.png';
      final String filePath = '${directory.path}/$fileName';

      final File file = File(filePath);
      await file.writeAsBytes(pngBytes);

      setState(() {
        _exporting = false;
        _exportPath = filePath;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logo exported to $filePath')));
      }
    } catch (e) {
      setState(() {
        _exporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}
