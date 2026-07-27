import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de release — lit android/key.properties (fichier local, JAMAIS
// commité) si présent. Sans ce fichier, on retombe sur la signature debug
// pour ne pas casser `flutter run` avant que le keystore ne soit généré.
// Même pattern que courrier_client et courrier_livreur — avant ce fix,
// cette app était signée en debug de façon inconditionnelle, sans même
// cette option de repli propre.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.tibus.courrier"
    // Forcé à 36 (au lieu de flutter.compileSdkVersion) : plusieurs
    // dépendances transitives de flutter_pos_printer_platform_image_3
    // (androidx.arch.core, androidx.window.extensions.core...) exigent un
    // compileSdk >= 33 côté app consommatrice, sinon échec de build Gradle
    // ("requires libraries and applications that depend on it to compile
    // against version 33 or later").
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requis par flutter_local_notifications (desugaring des API Java 8+
        // pour le support des notifications programmées / canaux).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tibus.courrier"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signature de release réelle si android/key.properties existe,
            // repli sur la clé debug sinon (voir commentaire plus haut).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // SDK imprimante P3/Wiseasy (Wangpos) — repris tel quel de tibus-v2-HUB
    // (app/libs/). NE PAS SUPPRIMER : nécessaire à P3PrinterModule.kt.
    // Sans effet sur iOS/web, ni sur un appareil Android sans ce hardware
    // (voir printer_service.dart : no-op si le canal échoue).
    implementation(fileTree("libs") { include("*.aar", "*.jar") })
    // Requis par P3PrinterChannel.kt (appels SDK hors thread UI).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // Requis par flutter_local_notifications (isCoreLibraryDesugaringEnabled ci-dessus).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
