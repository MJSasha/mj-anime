import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("../.signing/key.properties")
val signingProperties = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}

android {
    namespace = "dev.independent.animetka_tv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.independent.animetka_tv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        ndk { abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a")) }
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("independentRelease") {
            if (signingFile.exists()) {
                // Keep the same private key even after moving the checkout.
                storeFile = rootProject.file("../.signing/release.jks")
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }
    packaging { jniLibs { excludes.addAll(listOf("**/x86_64/**", "**/x86/**")) } }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.isReturnDefaultValues = true
    }
    buildTypes {
        release {
            signingConfig = if (signingFile.exists()) signingConfigs.getByName("independentRelease") else null
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
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.23.0")
    testImplementation("org.robolectric:robolectric:4.17")
}
