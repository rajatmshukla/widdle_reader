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
    namespace = "com.widdlereader.app" // Changed from com.example.widdle_reader
    // Explicitly set compileSdk version
    compileSdk = 35

    // *** Explicitly set NDK version required by plugins ***
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Set source and target compatibility to Java 17
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // Set Kotlin JVM target to Java 17
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.widdlereader.app" // Changed from com.example.widdle_reader
        minSdk = 28 // Changed to 28 to support Android 9 (API 28)
        targetSdk = 35
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
        multiDexEnabled = true // Enable MultiDex
    }

    signingConfigs {
         // Ensure debug signing config exists (usually default)
         // debug {
         // }
         create("release") {
             val keystorePropertiesFile = rootProject.file("keystore.properties")
             if (keystorePropertiesFile.exists()) {
                 val keystoreProperties = Properties()
                 keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                 
                 storeFile = file(keystoreProperties["storeFile"] ?: "../../widdle_reader.keystore")
                 storePassword = keystoreProperties["storePassword"] as String
                 keyAlias = keystoreProperties["keyAlias"] as String
                 keyPassword = keystoreProperties["keyPassword"] as String
             } else {
                 // Fallback for CI/CD environments using environment variables
                 storeFile = file(System.getenv("KEYSTORE_FILE") ?: "../../widdle_reader.keystore")
                 storePassword = System.getenv("KEYSTORE_PASSWORD")
                 keyAlias = System.getenv("KEY_ALIAS")
                 keyPassword = System.getenv("KEY_PASSWORD")
             }
         }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")

            // TODO: Configure your release signing key
             signingConfig = signingConfigs.getByName("release")
             
             // Generate native debug symbols for Play Store
             ndk {
                 debugSymbolLevel = "FULL"
             }
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1") // Add MultiDex support library
    
    // Media and Audio Service dependencies
    implementation("androidx.media:media:1.7.0") // Updated Media support for audio service
    implementation("androidx.media3:media3-session:1.2.0") // Media3 for better Android Auto support
    
    // Note: androidx.car.app:app dependency REMOVED to prevent automotive feature declaration
    // App uses MediaBrowserServiceCompat (from androidx.media) for Android Auto support
    // This prevents conflict between automotive hardware feature and Android Auto metadata
    
    // Google Play Services
    implementation("com.google.android.gms:play-services-auth:20.7.0") // Google Play Services for licensing
    
    // Coroutines for async operations
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    
    // JSON processing
    implementation("com.google.code.gson:gson:2.10.1")
    
    // Add other app-specific dependencies here if needed
}