// *** ADD these imports at the very top ***
import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile // If using Kotlin specific tasks later

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Function to read local properties file
fun getLocalProperty(key: String, project: org.gradle.api.Project): String {
    // Use the imported Properties class
    val properties = Properties()
    val localPropertiesFile = project.rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        // Use the imported FileInputStream class
        properties.load(FileInputStream(localPropertiesFile))
        return properties.getProperty(key) ?: ""
    }
    return ""
}

// Read flutter SDK path from local.properties
val flutterSdkPath by extra(getLocalProperty("flutter.sdk", project))

// Read flutter properties from SDK path
val flutterVersionCode by extra {
    getLocalProperty("flutter.versionCode", project).takeIf { it.isNotEmpty() } ?: "1"
}

val flutterVersionName by extra {
    getLocalProperty("flutter.versionName", project).takeIf { it.isNotEmpty() } ?: "1.0"
}

// Determine compileSdkVersion and targetSdkVersion from Flutter framework
val compileSdkVersionFromFlutter by extra {
     project.properties["android.compileSdkVersion"]?.toString()?.toIntOrNull() ?: 34 // Default 34
}
val targetSdkVersionFromFlutter by extra {
     project.properties["android.targetSdkVersion"]?.toString()?.toIntOrNull() ?: 34 // Default 34
}
// Determine minSdkVersion from Flutter framework
val minSdkVersionFromFlutter by extra {
    project.properties["android.minSdkVersion"]?.toString()?.toIntOrNull() ?: 21 // Default 21
}


android {
    // Set namespace (ensure this matches your AndroidManifest.xml package)
    namespace = "com.example.widdle_reader" // <-- Verify/Change this if needed
    // Explicitly set compileSdk version
    compileSdk = 35

    // *** Explicitly set NDK version required by plugins ***
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Set source and target compatibility to Java 17
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // Set Kotlin JVM target to Java 17
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.widdle_reader" // <-- Verify/Change this if needed
        minSdk = minSdkVersionFromFlutter
        targetSdk = 35
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
        multiDexEnabled = true // Enable MultiDex
    }

    signingConfigs {
         // Ensure debug signing config exists (usually default)
         // You WILL need to configure release signing later for production builds
         // debug {
         // }
         // release {
              // TODO: Add your release signing configuration
         // }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")

            // TODO: Configure your release signing key
             signingConfig = signingConfigs.getByName("debug") // Using debug for now
            // signingConfig = signingConfigs.getByName("release")
        }
        debug {
             // signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Flutter plugin integration settings
flutter {
    source = "../.."
}

// App dependencies
dependencies {
    implementation(kotlin("stdlib-jdk8")) // Use Kotlin standard library
    implementation("androidx.multidex:multidex:2.0.1") // Add MultiDex support library
    // Add other app-specific dependencies here if needed
}