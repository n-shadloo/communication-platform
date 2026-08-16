plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val nativeCryptoRoot = rootProject.layout.buildDirectory.dir("rust-android").get().asFile
val nativeCryptoFoundationJniLibs = nativeCryptoRoot.resolve("foundation/jniLibs")
val nativeCryptoBetaJniLibs = nativeCryptoRoot.resolve("beta/jniLibs")
val isWindowsHost = System.getProperty("os.name").lowercase().contains("windows")

fun registerRustCryptoBuild(
    taskName: String,
    cryptoProfile: String,
    outputDirectory: File,
) = tasks.register<Exec>(taskName) {
    group = "build"
    description = "Builds the pinned $cryptoProfile Rust cryptographic core for Android."
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
    outputs.dir(outputDirectory)

    if (isWindowsHost) {
        commandLine(
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            toolDirectory.resolve("build_rust_android.ps1").absolutePath,
            "all",
            cryptoProfile,
        )
    } else {
        commandLine(
            "bash",
            toolDirectory.resolve("build_rust_android.sh").absolutePath,
            "all",
            cryptoProfile,
        )
    }
}

val buildRustCryptoAndroid = registerRustCryptoBuild(
    "buildRustCryptoAndroid",
    "foundation",
    nativeCryptoFoundationJniLibs,
)
val buildRustCryptoAndroidBeta = registerRustCryptoBuild(
    "buildRustCryptoAndroidBeta",
    "beta",
    nativeCryptoBetaJniLibs,
)

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

    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            applicationId = "$placeholderProductionApplicationId.development"
            resValue("string", "app_name", "Communication Platform (Development)")
        }
        create("beta") {
            dimension = "environment"
            applicationId = "$placeholderProductionApplicationId.beta"
            resValue("string", "app_name", "Communication Platform (Closed Beta)")
        }
        create("production") {
            dimension = "environment"
            applicationId = placeholderProductionApplicationId
            resValue("string", "app_name", "Communication Platform")
        }
    }

    sourceSets.getByName("development").jniLibs.srcDir(nativeCryptoFoundationJniLibs)
    sourceSets.getByName("production").jniLibs.srcDir(nativeCryptoFoundationJniLibs)
    sourceSets.getByName("beta").jniLibs.srcDir(nativeCryptoBetaJniLibs)

    buildTypes {
        release {
            // Production signing is intentionally deferred to the reviewed release piece.
        }
    }
}

dependencies {
    // FileProvider is used for scoped, read-only attachment sharing. Keep the
    // dependency explicit so this security boundary does not rely on a
    // transitive Flutter/plugin dependency.
    implementation("androidx.core:core:1.16.0")
}

tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("JniLibFolders")) {
        dependsOn(
            if (name.startsWith("mergeBeta")) {
                buildRustCryptoAndroidBeta
            } else {
                buildRustCryptoAndroid
            },
        )
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
