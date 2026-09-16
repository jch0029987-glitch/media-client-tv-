import org.gradle.api.Action
import org.gradle.api.Project

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

// Force all subprojects (including serious_python_android) to compile against SDK 36
subprojects {
    afterEvaluate(object : Action<Project> {
        override fun execute(p: Project) {
            p.pluginManager.withPlugin("com.android.library") {
                val androidExt = p.extensions.findByName("android")
                if (androidExt != null) {
                    try {
                        val setCompileSdk = androidExt::class.java.getMethod("setCompileSdk", Int::class.java)
                        setCompileSdk.invoke(androidExt, 36)
                    } catch (e: Exception) {
                        try {
                            val setCompileSdkVersion = androidExt::class.java.getMethod("setCompileSdkVersion", Int::class.java)
                            setCompileSdkVersion.invoke(androidExt, 36)
                        } catch (ignored: Exception) {}
                    }
                }
            }
        }
    })
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
