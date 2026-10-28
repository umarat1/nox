plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: the Nox key (lumen.jks), same certificate as Nox 0.7.x so 1.0 installs
// over it. Paths/passwords come only from the environment (see scripts/build-android.sh);
// without them the release build falls back to the debug key and must not be shipped.
val ksPath: String? = System.getenv("NOX_KS_PATH")

android {
    namespace = "com.lumen.vpn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lumen.vpn"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // pubspec build 2110. Split APKs become abi*1000+2110 (v7a 3110, arm64 4110),
        // both above 1.0.30. versionName stays "2.1" (pubspec 2.1.0 is only the semver triple).
        versionCode = flutter.versionCode
        versionName = "2.1.1"
        // ABIs come from `flutter build apk --split-per-abi --target-platform android-arm,android-arm64`.
        // Setting ndk.abiFilters here conflicts with those splits on AGP 9.
    }

    signingConfigs {
        create("nox") {
            if (ksPath != null) {
                storeFile = file(ksPath)
                storePassword = System.getenv("NOX_KS_PASS")
                keyAlias = System.getenv("NOX_KEY_ALIAS")
                keyPassword = System.getenv("NOX_KEY_PASS")
            }
            // 1.0.23 shipped v2-only. OxygenOS verifies v2+v3; v1 is unused at minSdk 24.
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = false
        }
    }

    buildTypes {
        release {
            signingConfig = if (ksPath != null) signingConfigs.getByName("nox") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    sourceSets {
        getByName("main") {
            // Stripped copies (scripts/stage-android-jni.sh). A File, not a Provider:
            // AGP 9 rejects Provider instances on the SourceSet API.
            jniLibs.srcDir(layout.buildDirectory.dir("nox-jni").get().asFile)
        }
    }

    packaging {
        jniLibs {
            // Uncompressed and 16 KB zip-aligned. The 1.0.23 APK stored every .so
            // compressed (extractNativeLibs=true), so the installer unpacked ~187 MB
            // (libnox 108 MB) and OxygenOS never finished. mmap from the APK instead.
            useLegacyPackaging = false
        }
    }
}

val stageNoxJni = tasks.register<Exec>("stageNoxJni") {
    val script = rootProject.file("../../scripts/stage-android-jni.sh")
    val out = layout.buildDirectory.dir("nox-jni")
    inputs.dir(rootProject.file("../../third_party/android"))
    outputs.dir(out)
    commandLine("bash", script.absolutePath, out.get().asFile.absolutePath)
}

tasks.configureEach {
    if (name.contains("JniLib") || name.contains("NativeLibs")) {
        dependsOn(stageNoxJni)
    }
}
tasks.named("preBuild").configure { dependsOn(stageNoxJni) }

dependencies {
    implementation(files("libs/noxcore.aar")) // Go engine + sing-box (go/mobile/build-aar.sh)
    implementation("androidx.core:core:1.17.0")
    // QR scanner for «Передать на ТВ» (camera asked only when scanning)
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
