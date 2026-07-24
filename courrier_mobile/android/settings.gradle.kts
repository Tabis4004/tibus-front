pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
         // Ajouts requis pour xprinter_sdk
        maven {
            url "${project(':aar').projectDir}/build" // pour build.gradle
            // url = uri(project(":xprinter_sdk").projectDir.resolve("mvn")) // (si build.gradle.kts)
        }
        maven { url 'https://jitpack.io' }
    }

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9.0.1 + Kotlin 2.3.20 (versions les plus récentes) déclenchent le
    // nouveau modèle "built-in Kotlin" d'AGP 9 — mobile_scanner (encore sur
    // l'ancien modèle Kotlin Gradle Plugin classique, voir
    // https://github.com/juliansteenbakker/mobile_scanner/issues/1708, bug
    // ouvert non résolu par ses mainteneurs) échoue alors avec "Could not
    // find method kotlin() for arguments" dans son propre build.gradle.
    // Redescendu sur AGP 8.13 (supporte compileSdk 36, cf.
    // android/build.gradle.kts) + Kotlin 2.1.20 : combinaison mature,
    // largement testée par l'écosystème des plugins Flutter tiers.
    id("com.android.application") version "8.13.0" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.4") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
}

include(":app")
