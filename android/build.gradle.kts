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

// Force all subproject libraries (like serious_python_android) to compile against SDK 36
subprojects {
    afterEvaluate { p ->
        p.plugins.withId("com.android.library") {
            p.extensions.findByName("android")?.let { androidExt ->
                try {
                    val getMethod = androidExt.javaClass.getMethod("getCompileSdk")
                    val setMethod = androidExt.javaClass.getMethod("setCompileSdk", Int::class.java)
                    val currentSdk = getMethod.invoke(androidExt) as? Int
                    if (currentSdk == null || currentSdk < 36) {
                        setMethod.invoke(androidExt, 36)
                    }
                } catch (e: Exception) {
                    // Ignored if reflection fails
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
