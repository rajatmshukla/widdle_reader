import 'package:flutter/material.dart';
import 'dart:math';
import '../utils/helpers.dart';

class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onChanged; // Callback when user starts dragging
  final ValueChanged<Duration>?
  onChangeEnd; // Callback when user finishes dragging

  const SeekBar({
    super.key,
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  SeekBarState createState() => SeekBarState();
}

class SeekBarState extends State<SeekBar> {
  double? _dragValue;
  bool _dragging = false; // Track drag state

  @override
  Widget build(BuildContext context) {
    final value = min(
      _dragValue ?? widget.position.inMilliseconds.toDouble(),
      widget.duration.inMilliseconds.toDouble(),
    );

    // Ensure value is not negative
    final clampedValue = max(0.0, value);
    final maxDuration = widget.duration.inMilliseconds.toDouble();
    // Ensure maxDuration is not zero to avoid division by zero
    final double sliderMaxValue = maxDuration > 0 ? maxDuration : 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15.0),
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.grey[700],
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.2),
            // Custom Tick Mark Shape for Buffered Position (if desired)
            // activeTickMarkColor: Colors.white.withOpacity(0.7),
            // inactiveTickMarkColor: Colors.transparent,
            // tickMarkShape: RoundSliderTickMarkShape(tickMarkRadius: 2.0),
          ),
          child: Slider(
            min: 0.0,
            max: sliderMaxValue,
            value: clampedValue.clamp(0.0, sliderMaxValue),
            // Secondary (buffered) value - ensure it's clamped as well
            secondaryTrackValue: min(
              widget.bufferedPosition.inMilliseconds.toDouble(),
              sliderMaxValue,
            ).clamp(0.0, sliderMaxValue),
            onChanged: (newValue) {
              if (!_dragging) {
                _dragging = true;
              }
              setState(() {
                _dragValue = newValue;
              });
              if (widget.onChanged != null) {
                widget.onChanged!(Duration(milliseconds: newValue.round()));
              }
            },
            onChangeEnd: (newValue) {
              if (widget.onChangeEnd != null) {
                widget.onChangeEnd!(Duration(milliseconds: newValue.round()));
              }
              _dragging = false;
              _dragValue = null; // Reset drag value after seeking
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(Duration(milliseconds: clampedValue.round())),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                formatDuration(widget.duration),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Helper stream class to combine position, buffered position and duration
class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}
