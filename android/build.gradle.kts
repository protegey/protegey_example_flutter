allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// flutter_jailbreak_detection 1.10.0 (a protegey_sdk dependency, for the isRooted device-intel
// field) predates AGP's namespace requirement and has no `namespace` in its own build.gradle —
// AGP 8+ refuses to configure it without one. Supplying it here (matching the package declared in
// that plugin's own AndroidManifest.xml) is the standard workaround for abandoned plugins like
// this, since we don't control its source. Registered before evaluationDependsOn(":app") below,
// which forces this plugin's evaluation early — afterEvaluate must be hooked before that happens.
subprojects {
    afterEvaluate {
        if (project.name == "flutter_jailbreak_detection") {
            val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            if (android != null && android.namespace == null) {
                android.namespace = "appmire.be.flutterjailbreakdetection"
            }
            // Same abandoned-plugin gap: its Java compile task defaults to the ancient 1.8
            // target while its Kotlin compile task defaults to whatever JDK is running the
            // build (17 here) — AGP refuses to mix the two. Force both to 17.
            android?.compileOptions?.apply {
                sourceCompatibility = org.gradle.api.JavaVersion.VERSION_17
                targetCompatibility = org.gradle.api.JavaVersion.VERSION_17
            }
            project.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
