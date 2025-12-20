import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/simple_audio_service.dart';
import '../services/storage_service.dart';

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key});

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  final SimpleAudioService _audioService = SimpleAudioService();
  final StorageService _storageService = StorageService();
  
  bool _isLoading = true;
  bool _isSupported = false;
  bool _isEnabled = false;
  List<AndroidEqualizerBand> _bands = [];
  double _volumeBoost = 0.0;
  
  // Local state for sliders to be responsive
  List<double> _bandGains = []; // Matches _bands length

  final Map<String, List<double>> _presets5Band = {
    'Flat': [0, 0, 0, 0, 0],
    'Vocal Boost': [-3, 0, 4, 5, 2], // Cut mud, boost presence
    'Commute': [-10, -5, 0, 3, 2], // Cut rumble
    'Soft': [-2, -1, 0, -3, -6], // Rolloff highs
    'Podcast': [2, 1, 3, 2, 0], // Warmer voice
  };

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final enabled = await _audioService.getEqualizerEnabled();
      final bands = await _audioService.getEqualizerBands();
      final boost = await _audioService.getVolumeBoost();
      
      // Get current audiobook ID for per-book settings
      final audiobookId = _audioService.currentAudiobook?.id;
      
      // Retrieve gains from storage for this specific book
      final storedGains = await _storageService.getEqualizerBandGains(audiobookId: audiobookId);
      
      if (mounted) {
        setState(() {
          _isEnabled = enabled;
          _bands = bands;
          _volumeBoost = boost;
          _isSupported = bands.isNotEmpty;
          
          _bandGains = List.filled(bands.length, 0.0);
          // Apply stored gains if matching length
          storedGains.forEach((k, v) {
            if (k < _bandGains.length) _bandGains[k] = v;
          });
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading EQ state: $e");
      if (mounted) {
        setState(() {
          _isSupported = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isSupported) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.equalizer_rounded, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              "Equalizer not supported on this device",
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Audio Effects",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: _isEnabled,
                  onChanged: (val) {
                    setState(() => _isEnabled = val);
                    _audioService.setEqualizerEnabled(val);
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Presets
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: _presets5Band.keys.map((name) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(name),
                    selected: false, // Could track selected preset logic
                    onSelected: _isEnabled ? (_) => _applyPreset(name) : null,
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 32),

          // Equalizer Sliders
          if (_bands.isNotEmpty)
            SizedBox(
              height: 200,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_bands.length, (index) {
                  final band = _bands[index];
                  // Freq label: e.g. 60000 -> 60Hz or 60000 mHz? 
                  // just_audio: centerFrequency is in milliHertz
                  final freqHz = band.centerFrequency / 1000;
                  String label = freqHz >= 1000 
                      ? '${(freqHz / 1000).toStringAsFixed(1)}k' 
                      : '${freqHz.round()}';

                  return Column(
                    children: [
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              activeTrackColor: theme.colorScheme.primary,
                              inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
                            ),
                            child: Slider(
                              value: _bandGains[index].clamp(-10.0, 10.0),
                              min: -10.0,
                              max: 10.0,
                              onChanged: _isEnabled ? (val) {
                                setState(() => _bandGains[index] = val);
                                _audioService.setBandGain(index, val);
                              } : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _isEnabled 
                              ? theme.colorScheme.onSurface 
                              : theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_bandGains[index] > 0 ? '+' : ''}${_bandGains[index].round()}dB',
                         style: theme.textTheme.bodySmall?.copyWith(
                           fontSize: 10,
                           color: theme.colorScheme.outline,
                         ),
                      ),
                    ],
                  );
                }),
              ),
            ),

          const SizedBox(height: 32),

          // VOLUME BOOST Slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Volume Boost",
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      "${(_volumeBoost * 10).round()}%", // Display approximate percentage
                       style: theme.textTheme.bodyMedium?.copyWith(
                         fontWeight: FontWeight.bold,
                         color: _volumeBoost > 0 ? theme.colorScheme.primary : theme.colorScheme.outline,
                       ),
                    ),
                  ],
                ),
                Slider(
                  value: _volumeBoost,
                  min: 0.0,
                  max: 15.0, // Limit to 15dB boost max for safety
                  divisions: 15,
                  label: "${_volumeBoost.round()} dB",
                  onChanged: _isEnabled ? (val) {
                    setState(() => _volumeBoost = val);
                    _audioService.setVolumeBoost(val);
                  } : null,
                ),
                Text(
                  "Warning: High boost levels may distort audio.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _applyPreset(String name) {
    final values = _presets5Band[name];
    if (values != null && values.length == _bands.length) {
      setState(() {
        for (int i = 0; i < values.length; i++) {
          _bandGains[i] = values[i];
          _audioService.setBandGain(i, values[i]);
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preset not compatible with this device")),
      );
    }
  }
}

// Extension to access internal storage for UI init
extension StorageAccess on SimpleAudioService {
  // This is a hack because _storageService is private.
  // Ideally, SimpleAudioService should expose `getEqualizerParameters()` returning a Map.
  // But since I can't edit SimpleAudioService easily again right now without context switching, 
  // I'll rely on what I exposed: I exposed getters for boost and enabled.
  // I missed `getEqualizerBandGains`.
  // I'll define a getter via `getEqualizerBandGains` if I added it to SimpleAudioService? 
  // I didn't add `getEqualizerBandGains` to AudioService, only `getEqualizerBands`.
  // So I need to use `StorageService` directly? 
  // No, I can't access private members.
  // I'll assume 0.0 for now if not available, it will correct itself when user touches it.
  // Actually, I can use `getEqualizerBands` from just_audio which has params. 
  // But just_audio params might not reflect my manual storage if not synced.
  // Let's assume 0 for init.
}

// Extension is unnecessary, we'll handle gracefully.
