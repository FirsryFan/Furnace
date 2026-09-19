allprojects {
    repositories {
        // `google()` is redirected to the CDN host by
        // gradle/google-cdn.init.gradle (maven.google.com is unreachable here).
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
    project.evaluationDependsOn(":app")
}

// Plugin compileSdk alignment is handled by
// gradle/google-cdn.init.gradle (`gradle.beforeProject`), because it has to run
// BEFORE each plugin's own build.gradle is evaluated. Doing it here is too late
// in either direction:
//   * `subprojects { afterEvaluate { ... } }` throws
//     "Cannot run Project.afterEvaluate(Action) when the project is already
//     evaluated" (the `evaluationDependsOn(":app")` above already evaluated them);
//   * `gradle.projectsEvaluated { ... }` throws
//     "It is too late to set compileSdk / It has already been read".

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
