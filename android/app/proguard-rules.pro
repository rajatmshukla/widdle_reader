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

# Add project specific ProGuard rules here.

# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep the LVL classes completely unchanged
-keep class com.android.vending.licensing.** { *; }
-dontwarn com.android.vending.licensing.**

# Flutter secure storage rules
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Just Audio rules
-keep class com.ryanheise.** { *; }

# Media session
-keep class android.support.v4.media.** { *; }
-keep class androidx.media.** { *; }

# Obfuscate class names for additional security
-repackageclasses
-allowaccessmodification
-optimizationpasses 5

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep common classes used in serialization/reflection
-keepattributes *Annotation*,EnclosingMethod,Signature,InnerClasses,Exceptions
-keepnames class ** { *; }

# Keep public classes and methods (including application level classes)
-keep public class com.example.widdle_reader.** { 
    public *; 
}

# Strong constant obfuscation 
-keepclassmembers class * {
    static final %                *;
    static final java.lang.String *;
}

# Basic security measures against reversing
-dontskipnonpubliclibraryclasses
-allowaccessmodification
-mergeinterfacesaggressively
-overloadaggressively 