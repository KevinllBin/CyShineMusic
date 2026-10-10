package com.cyshine.music

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

internal class AppIconManager(context: Context) {
    private val context = context.applicationContext
    private val packageManager = this.context.packageManager
    private val preferences = this.context.getSharedPreferences("launcher_icon", Context.MODE_PRIVATE)
    private val aliases = linkedMapOf(
        "classic" to "ClassicIconAlias",
        "midnight" to "MidnightIconAlias",
        "sky" to "SkyIconAlias",
        "lavender" to "LavenderIconAlias",
        "mint" to "MintIconAlias",
        "peach" to "PeachIconAlias",
    ).mapValues { (_, name) ->
        ComponentName(this.context.packageName, "${MainActivity::class.java.name.substringBeforeLast('.')}.$name")
    }

    fun currentIcon(): String {
        val enabled = aliases.keys.filter(::isEnabled)
        val saved = preferences.getString("selected", null)
        return saved?.takeIf { it in enabled } ?: enabled.firstOrNull() ?: "classic"
    }

    fun setIcon(code: String): String {
        require(code in aliases) { "Unknown app icon: $code" }
        val previous = aliases.mapValues { (_, component) -> packageManager.getComponentEnabledSetting(component) }
        val desired = aliases.mapValues { (id, _) ->
            if (id == code) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        try {
            applyStates(desired, code)
        } catch (error: Exception) {
            // On older Android versions a sequence can fail partway through.
            // Restore enabled entries first so there is always a launcher entry.
            val restoreFirst = previous.keys.firstOrNull { id ->
                previous[id] == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                    (previous[id] == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && id == "classic")
            } ?: "classic"
            try {
                applyStates(previous, restoreFirst)
            } catch (rollback: Exception) {
                error.addSuppressed(rollback)
            }
            throw error
        }
        preferences.edit().putString("selected", code).apply()
        return code
    }

    private fun isEnabled(code: String): Boolean {
        return when (packageManager.getComponentEnabledSetting(aliases.getValue(code))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> code == "classic"
            else -> false
        }
    }

    private fun applyStates(states: Map<String, Int>, first: String) {
        val changed = states.filter { (id, state) ->
            packageManager.getComponentEnabledSetting(aliases.getValue(id)) != state
        }
        if (changed.isEmpty()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.setComponentEnabledSettings(changed.map { (id, state) ->
                PackageManager.ComponentEnabledSetting(aliases.getValue(id), state, PackageManager.DONT_KILL_APP)
            })
        } else {
            // Enable the new alias before disabling the previous launcher entry.
            changed.keys.sortedBy { if (it == first) 0 else 1 }.forEach { id ->
                packageManager.setComponentEnabledSetting(
                    aliases.getValue(id), states.getValue(id), PackageManager.DONT_KILL_APP,
                )
            }
        }
    }
}
