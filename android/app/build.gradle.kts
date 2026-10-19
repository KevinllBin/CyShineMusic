import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun currentGitBranch(): String? = runCatching {
    val process = ProcessBuilder("git", "rev-parse", "--abbrev-ref", "HEAD")
        .directory(rootProject.projectDir.parentFile)
        .redirectErrorStream(true)
        .start()
    process.inputStream.bufferedReader().use { it.readText() }.trim()
        .takeIf { process.waitFor() == 0 }
}.getOrNull()

val appChannel = (
    providers.gradleProperty("app.channel").orNull
        ?: System.getenv("APP_CHANNEL")
        ?: when (currentGitBranch()) {
            "dev" -> "dev"
            "codex/liquid-glass-refactor" -> "glass"
            else -> "main"
        }
    ).trim().lowercase()
require(appChannel in setOf("main", "dev", "glass")) {
    "app.channel must be 'main', 'dev', or 'glass', but was '$appChannel'."
}

val appId = when (appChannel) {
    "dev" -> "com.cyshine.music.dev"
    "glass" -> "com.cyshine.music.glass"
    else -> "com.cyshine.music"
}
val appLabel = when (appChannel) {
    "dev" -> "栖弦dev"
    "glass" -> "栖弦-液态玻璃"
    else -> "栖弦"
}

val targetPlatformToAbi = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
)
val requestedAbis = (project.findProperty("target-platform") as? String)
    ?.split(",")
    ?.mapNotNull { targetPlatformToAbi[it.trim()] }
    ?.toSet()
    ?.takeIf { it.isNotEmpty() }
    ?: setOf("arm64-v8a")
val splitPerAbi = project.findProperty("split-per-abi") == "true"

// The glass app has its own install identity and reuses the fixed dev key.
val signingChannel = if (appChannel == "glass") "dev" else appChannel
val signingPropertiesFile = rootProject.file("signing/$signingChannel.properties")
val signingProperties = Properties().apply {
    if (signingPropertiesFile.isFile) {
        signingPropertiesFile.inputStream().use(::load)
    }
}
val signingStoreFile = signingProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { path ->
        File(path).let { file ->
            if (file.isAbsolute) file else signingPropertiesFile.parentFile.resolve(path)
        }
    }
val signingStorePassword = signingProperties.getProperty("storePassword")
val signingKeyAlias = signingProperties.getProperty("keyAlias")
val signingKeyPassword = signingProperties.getProperty("keyPassword")
val releaseSigningReady = signingStoreFile?.isFile == true &&
    !signingStorePassword.isNullOrBlank() &&
    !signingKeyAlias.isNullOrBlank() &&
    !signingKeyPassword.isNullOrBlank()

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

    signingConfigs {
        if (releaseSigningReady) {
            create("channelRelease") {
                storeFile = requireNotNull(signingStoreFile)
                storePassword = signingStorePassword
                keyAlias = signingKeyAlias
                keyPassword = signingKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = appId
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = appLabel
    }

    buildTypes {
        release {
            // ABI splits already select the packaged architectures. AGP rejects
            // combining them with an NDK abiFilters selection, even for debug.
            if (!splitPerAbi) {
                ndk {
                    abiFilters.clear()
                    abiFilters += requestedAbis
                }
            }
            if (releaseSigningReady) {
                signingConfig = signingConfigs.getByName("channelRelease")
            }
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

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.project == project && task.name.contains("release", ignoreCase = true)
    }
    if (buildsRelease && !releaseSigningReady) {
        throw GradleException(
            "Missing fixed $appChannel signing configuration. " +
                "Create ${signingPropertiesFile.path} and its referenced keystore.",
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Compile against jaudiotagger without bundling another copy. The
    // flutter_audio_tagger plugin already packages jaudiotagger-android.jar;
    // our app channel uses the same runtime classes but avoids returning the
    // whole edited audio file through MethodChannel.
    compileOnly("net.jthink:jaudiotagger:3.0.1")
}
