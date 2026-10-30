plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pl.pwr.neurotchi.neurotchi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pl.pwr.neurotchi.neurotchi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// BrainAccessKit (licencja: tylko jako czesc aplikacji) lezy w archive/, rozpakowywany do vendor/.
val kitZip = rootProject.file("../../archive/BrainAccessKit-2.2.0.zip")
val kitLibs = rootProject.file("../../vendor/android/libs")
val extractKit by tasks.registering(Copy::class) {
    onlyIf { !kitLibs.resolve("core-release.aar").exists() }
    from(zipTree(kitZip)) {
        include("*/libs/*")
        eachFile { path = name }
        includeEmptyDirs = false
    }
    into(kitLibs)
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(extractKit) }

dependencies {
    implementation(fileTree(mapOf("dir" to kitLibs, "include" to listOf("core-release.aar", "transport-android-release.aar", "protocol-*.jar"))))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("no.nordicsemi.android:ble:2.9.0")
    implementation("no.nordicsemi.android:ble-ktx:2.9.0")
}
