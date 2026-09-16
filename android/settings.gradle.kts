plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.1.1" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}

include(":app")

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Dynamically force all library subprojects (like serious_python_android) to SDK 36
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
                    // Fallback
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
