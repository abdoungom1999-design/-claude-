plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "sn.groupesantine.sprint"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "sn.groupesantine.sprint"
        // Firebase (Auth, Firestore, Functions) exige Android 6.0 au minimum.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // La CI passe --build-number (numéro du run) : chaque APK a un
        // numéro de version plus grand que le précédent, ce qui permet de
        // l'installer par-dessus l'ancien.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signature de l'APK distribué aux chauffeurs : la clé est gardée dans
    // Google Secret Manager et fournie par la CI (variables ci-dessous),
    // jamais dans le dépôt. Toujours la même clé : chaque nouvelle version
    // s'installe par-dessus la précédente sans perdre la connexion.
    // Sans ces variables (poste de développement), clé de debug.
    val cleSignature = System.getenv("SPRINT_KEYSTORE_PATH")
    signingConfigs {
        if (cleSignature != null) {
            create("sprint") {
                storeFile = file(cleSignature)
                storePassword = System.getenv("SPRINT_KEYSTORE_PASSWORD")
                keyAlias = "sprint"
                keyPassword = System.getenv("SPRINT_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (cleSignature != null) signingConfigs.getByName("sprint")
                else signingConfigs.getByName("debug")
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
