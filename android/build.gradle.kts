allprojects {
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

// Force all library subprojects (like serious_python_android) to compile against SDK 36 safely
subprojects {
    afterEvaluate { project: org.gradle.api.Project ->
        project.pluginManager.withPlugin("com.android.library") {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val getMethod = (androidExt as Any).javaClass.getMethod("getCompileSdk")
                    val setMethod = (androidExt as Any).javaClass.getMethod("setCompileSdk", Int::class.java)
                    val currentSdk = getMethod.invoke(androidExt) as? Int
                    if (currentSdk == null || currentSdk < 36) {
                        setMethod.invoke(androidExt, 36)
                    }
                } catch (e: Exception) {
                    // Fallback gracefully if method signatures differ
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
