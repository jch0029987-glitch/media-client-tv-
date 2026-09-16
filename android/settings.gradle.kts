pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val file = file("local.properties")
        if (file.exists()) {
            properties.load(java.io.FileInputStream(file))
        }
        properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")
    }
    
    if (flutterSdkPath != null) {
        includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    }

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.1.1" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")
