plugins {
    id("com.android.library")
}

android {
    namespace = "com.un4seen.bass"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }
}

val verifyBassSslLibraries by tasks.registering {
    group = "verification"
    description = "Verify that BASS HTTPS support is bundled for every supported ABI."
    val sslLibraries = listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64").map { abi ->
        layout.projectDirectory.file("src/main/jniLibs/$abi/libbass_ssl.so")
    }
    inputs.files(sslLibraries)
    doLast {
        val missing = sslLibraries.filterNot { it.asFile.isFile }
        check(missing.isEmpty()) {
            "BASS HTTPS requires libbass_ssl.so for every supported ABI. Missing: " +
                missing.joinToString { it.asFile.relativeTo(projectDir).path }
        }
    }
}

tasks.named("preBuild") {
    dependsOn(verifyBassSslLibraries)
}
