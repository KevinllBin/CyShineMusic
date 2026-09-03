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

