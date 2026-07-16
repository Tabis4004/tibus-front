allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Fix: plusieurs plugins (flutter_pos_printer_platform_image_3,
// network_info_plus...) déclarent eux-mêmes un compileSdk trop bas dans leur
// propre build.gradle, alors que leurs dépendances transitives (androidx.core
// 1.13.1, lifecycle 2.7.0…) exigent compileSdk >= 33/34 — Gradle échoue sur
// checkReleaseAarMetadata module par module (whack-a-mole : corriger un seul
// module à la fois fait juste apparaître le suivant). On force donc
// compileSdk = 36 sur TOUS les sous-projets "library".
//
// (Un essai précédent excluait mobile_scanner de ce override, en supposant
// que CameraX régissait mal à un compileSdk forcé plus haut — un bug caméra
// identique (NPE générique "getClass() on a null object reference") a
// persisté à l'identique avec ou sans cette exclusion, ce qui invalide cette
// hypothèse : ce n'était pas le compileSdk. mobile_scanner a été mis à jour
// en 7.x séparément pour ce bug caméra — voir pubspec.yaml.)
//
// afterEvaluate {} est nécessaire ici (pas plugins.withId) : chaque script
// build.gradle de plugin applique `com.android.library` PUIS configure
// `android { compileSdk X }` plus bas dans SON PROPRE script — un override
// posé au moment de l'application du plugin (withId) serait donc écrasé
// juste après par cette ligne. afterEvaluate garantit qu'on s'exécute APRÈS
// que le script du plugin ait fini de tourner. (:app n'est pas concerné :
// déjà à compileSdk 36 dans app/build.gradle.kts, et évalué tôt via
// evaluationDependsOn ci-dessus — lui appliquer afterEvaluate planterait
// avec "already evaluated".)
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let {
                it.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
