pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val file = file("local.properties")
        if (file.exists()) {
            properties.load(java.io.FileInputStream(file))
        }
        properties.getProperty("flutter.sdk") ?: error("flutter.sdk not set in local.properties")
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.plugin-loader") version "1.0.0"
    id("com.android.application") version "7.3.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate { project ->
        project.plugins.withId("com.android.library") {
            project.extensions.findByName("android")?.let { androidExt ->
                try {
                    val compileSdkProp = androidExt.javaClass.getMethod("getCompileSdk")
                    val setCompileSdkMethod = androidExt.javaClass.getMethod("setCompileSdk", Int::class.java)
                    val currentSdk = compileSdkProp.invoke(androidExt) as? Int
                    if (currentSdk == null || currentSdk < 36) {
                        setCompileSdkMethod.invoke(androidExt, 36)
                    }
                } catch (e: Exception) {
                    // Fallback via reflection if standard method signature differs
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
