# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# AudioService package
-keep class com.ryanheise.audioservice.** { *; }
-keep public class com.ryanheise.** { *; }

# just_audio_background package
-keep class com.ryanheise.** { *; } 