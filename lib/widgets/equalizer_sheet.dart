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
  List<double> _bandGains = []; 
  String? _activePresetName;

  final Map<String, List<double>> _presets5Band = {
    'Flat': [0, 0, 0, 0, 0],
    'Vocal Boost': [-3, 0, 4, 5, 2],
    'Commute': [-10, -5, 0, 3, 2],
    'Soft': [-2, -1, 0, -3, -6],
    'Podcast': [2, 1, 3, 2, 0],
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
      
      final audiobookId = _audioService.currentAudiobook?.id;
      final storedGains = await _storageService.getEqualizerBandGains(audiobookId: audiobookId);
      final storedPreset = await _storageService.getEqualizerPreset(audiobookId: audiobookId);
      
      if (mounted) {
        setState(() {
          _isEnabled = enabled;
          _bands = bands;
          _volumeBoost = boost;
          _isSupported = bands.isNotEmpty;
          
          _bandGains = List.filled(bands.length, 0.0);
          storedGains.forEach((k, v) {
            if (k < _bandGains.length) _bandGains[k] = v;
          });
          
          _activePresetName = storedPreset;
          _isLoading = false;
          
          // If no preset saved but gains match one, detect it
          if (_activePresetName == null) {
            _detectActivePreset();
          }
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
    final colorScheme = theme.colorScheme;
    
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
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: _presets5Band.keys.map((name) {
                final isSelected = _activePresetName == name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: _isEnabled ? () => _applyPreset(name) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? colorScheme.primaryContainer 
                            : colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? colorScheme.primary : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            name,
                            style: TextStyle(
                              color: isSelected 
                                ? colorScheme.onPrimaryContainer 
                                : colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                                setState(() {
                                  _bandGains[index] = val;
                                  _activePresetName = null; 
                                });
                                _audioService.setBandGain(index, val);
                                _storageService.saveEqualizerPreset('', audiobookId: _audioService.currentAudiobook?.id);
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
                      "${_volumeBoost.round()} dB", 
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
                  max: 15.0, 
                  divisions: 15,
                  label: "${_volumeBoost.round()} dB",
                  onChanged: _isEnabled ? (val) {
                    setState(() {
                      _volumeBoost = val;
                    });
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
        _activePresetName = name;
        for (int i = 0; i < values.length; i++) {
          _bandGains[i] = values[i];
        }
        _audioService.setPresetGains(values);
      });
      _storageService.saveEqualizerPreset(name, audiobookId: _audioService.currentAudiobook?.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preset not compatible with this device")),
      );
    }
  }

  void _detectActivePreset() {
    if (_bands.isEmpty || _bandGains.isEmpty) return;
    
    String? detectedName;
    for (final entry in _presets5Band.entries) {
      final presetValues = entry.value;
      if (presetValues.length != _bandGains.length) continue;
      
      bool matches = true;
      for (int i = 0; i < presetValues.length; i++) {
        if ((presetValues[i] - _bandGains[i]).abs() > 0.1) {
          matches = false;
          break;
        }
      }
      
      if (matches) {
        detectedName = entry.key;
        break;
      }
    }
    
    setState(() {
      _activePresetName = detectedName;
    });
  }
}
