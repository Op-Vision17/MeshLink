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
subprojects {
    val fixSubproject = {
        plugins.withId("com.android.library") {
            val android = extensions.getByType(com.android.build.api.dsl.LibraryExtension::class.java)
            android.compileSdk = 35
        }
        val android = extensions.findByName("android") as? com.android.build.api.dsl.CommonExtension<*, *, *, *, *, *>
        if (android != null && android.namespace == null) {
            android.namespace = "dev.isar.${project.name.replace("-", "_")}"
        }
    }
    if (state.executed) {
        fixSubproject()
    } else {
        afterEvaluate {
            fixSubproject()
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
