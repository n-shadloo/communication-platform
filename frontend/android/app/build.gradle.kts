plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.communication_platform"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val placeholderProductionApplicationId = "com.example.communication_platform"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        // Reserved example namespace: replace only after final branding is approved.
        applicationId = placeholderProductionApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            applicationId = "$placeholderProductionApplicationId.development"
            resValue("string", "app_name", "Communication Platform (Development)")
        }
        create("production") {
            dimension = "environment"
            applicationId = placeholderProductionApplicationId
            resValue("string", "app_name", "Communication Platform")
        }
    }

    buildTypes {
        release {
            // Production signing is intentionally deferred to the reviewed release piece.
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
