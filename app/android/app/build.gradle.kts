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
        // pubspec 1.0.0+100: above Nox 0.7.71 (versionCode 99)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("nox") {
            if (ksPath != null) {
                storeFile = file(ksPath)
                storePassword = System.getenv("NOX_KS_PASS")
                keyAlias = System.getenv("NOX_KEY_ALIAS")
                keyPassword = System.getenv("NOX_KEY_PASS")
            }
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
            // libqwdtt.so per ABI: an executable started by the engine from nativeLibraryDir
            jniLibs.srcDir("../../../third_party/android")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true // extract .so files: libqwdtt.so is exec()'d
        }
    }
}

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
