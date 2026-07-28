plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val nativeCryptoRoot = rootProject.layout.buildDirectory.dir("rust-android").get().asFile
val nativeCryptoJniLibs = nativeCryptoRoot.resolve("jniLibs")
val isWindowsHost = System.getProperty("os.name").lowercase().contains("windows")

val buildRustCryptoAndroid by tasks.registering(Exec::class) {
    group = "build"
    description = "Builds the pinned Rust cryptographic core for all supported Android ABIs."
    workingDir = rootProject.projectDir.parentFile

    val toolDirectory = rootProject.projectDir.parentFile.resolve("tool")
    val nativeDirectory = rootProject.projectDir.parentFile.resolve("native/crypto_core")
    inputs.files(
        rootProject.projectDir.parentFile.resolve("rust-toolchain.toml"),
        toolDirectory.resolve("build_libsodium_android.sh"),
        toolDirectory.resolve("build_rust_android.ps1"),
        toolDirectory.resolve("build_rust_android.sh"),
        nativeDirectory.resolve("Cargo.toml"),
        nativeDirectory.resolve("Cargo.lock"),
        nativeDirectory.resolve("build.rs"),
        nativeDirectory.resolve("include/communication_crypto.h"),
        nativeDirectory.resolve("vendor/libsodium/LATEST.tar.gz"),
        nativeDirectory.resolve("vendor/libsodium/LATEST.tar.gz.minisig"),
    )
    inputs.dir(nativeDirectory.resolve("src"))
    inputs.dir(nativeDirectory.resolve("vendor/mlkem-native/mlkem"))
    outputs.dir(nativeCryptoJniLibs)

    if (isWindowsHost) {
        commandLine(
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            toolDirectory.resolve("build_rust_android.ps1").absolutePath,
            "all",
        )
    } else {
        commandLine(
            "bash",
            toolDirectory.resolve("build_rust_android.sh").absolutePath,
            "all",
        )
    }
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
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    sourceSets.getByName("main").jniLibs.srcDir(nativeCryptoJniLibs)

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

tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("JniLibFolders")) {
        dependsOn(buildRustCryptoAndroid)
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
