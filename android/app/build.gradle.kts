plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cyshine.music"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.cyshine.music"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            ndk {
                abiFilters.clear()
                abiFilters += "arm64-v8a"
            }
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // jaudiotagger inside flutter_audio_tagger uses reflection to find
            // frame-body copy constructors. When R8 minifies the release
            // build, those classes get renamed (`a2.f` etc.) and the
            // reflective lookup throws `NoSuchMethodException`, which is why
            // released builds were silently producing files with no cover or
            // lyric tags. Keep R8 off by default; the keep rules in
            // proguard-rules.pro mean that re-enabling minification later
            // won't reintroduce the regression.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("wang.harlon.quickjs:wrapper-android:2.4.0")

    // Compile against jaudiotagger without bundling another copy. The
    // flutter_audio_tagger plugin already packages jaudiotagger-android.jar;
    // our app channel uses the same runtime classes but avoids returning the
    // whole edited audio file through MethodChannel.
    compileOnly("net.jthink:jaudiotagger:3.0.1")
}
