package com.cyshine.music

import android.app.Application

class CyShineApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AndroidCrashHandler.install(this)
    }
}
