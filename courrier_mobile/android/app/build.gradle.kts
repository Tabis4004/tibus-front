import java.util.Properties
import java.io.FileInputStream
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Marque active (sis, default, ...) — écrite dans branding/.current par
// tool/apply_brand.py à chaque build (voir build_client.sh, qui l'appelle
// AVANT `flutter build`). Sert à choisir applicationId + keystore de
// release ci-dessous, SANS jamais modifier ce fichier à la main : un
// applicationId Play Store est permanent une fois publié, donc SIS et Tibus
// ne peuvent pas partager celui-ci — chaque marque a le sien dans son
// brand.json (androidApplicationId). Une marque qui ne définit pas ce champ
// retombe sur com.tibus.courrier (comportement historique inchangé).
val brandingDir = rootProject.file("../branding")
val currentBrand = brandingDir.resolve(".current")
    .let { if (it.exists()) it.readText().trim() else "" }
    .ifBlank { "default" }

val brandJsonFile = brandingDir.resolve("$currentBrand/brand.json")
val brandApplicationId: String = if (brandJsonFile.exists()) {
    @Suppress("UNCHECKED_CAST")
    val brand = JsonSlurper().parse(brandJsonFile) as Map<String, Any?>
    (brand["androidApplicationId"] as? String) ?: "com.tibus.courrier"
} else {
    "com.tibus.courrier"
}
// Diagnostic temporaire (2026-09-08) : le CI (Linux) est retombé sur
// com.tibus.courrier alors que la marque active était "sis" -- marchait en
// local (macOS). Ce println isole si le problème vient de la lecture de
// branding/.current, de brand.json, ou d'ailleurs, sans deviner à l'aveugle.
println("== branding diag : brandingDir=${brandingDir.absolutePath} exists=${brandingDir.exists()} " +
    "currentBrand=$currentBrand brandJsonFile=${brandJsonFile.absolutePath} " +
    "brandJsonExists=${brandJsonFile.exists()} brandApplicationId=$brandApplicationId ==")

// Signature de release — lit un keystore dédié à la marque active si
// présent (android/key.<marque>.properties, ex. key.sis.properties),
// sinon retombe sur android/key.properties (keystore historique unique,
// Tibus). Fichiers locaux, JAMAIS commités (voir android/.gitignore).
// Deux apps Play Store distinctes (applicationId différents) devraient
// avoir chacune leur propre clé de release plutôt que de la partager.
// Sans AUCUN des deux fichiers, on retombe sur la signature debug pour ne
// pas casser `flutter run` avant que le keystore n'existe.
val perBrandKeystoreFile = rootProject.file("key.$currentBrand.properties")
val keystorePropertiesFile =
    if (perBrandKeystoreFile.exists()) perBrandKeystoreFile else rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // Indépendant de applicationId ci-dessous (namespace = package interne
    // pour la génération de la classe R, invisible au Play Store et à
    // l'utilisateur ; applicationId = identifiant public de l'app). Les
    // deux n'ont pas besoin de correspondre depuis AGP 7+ — pas de dossier
    // Kotlin à déplacer quand une marque change d'applicationId.
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
        // Par marque active — voir brandApplicationId ci-dessus.
        applicationId = brandApplicationId
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
