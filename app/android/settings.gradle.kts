// NOTE ON REPOSITORIES
//
// `google()` resolves to maven.google.com, which is unreachable on this machine
// (`flutter doctor` reports "[!] Network resources ... maven.google.com:
// 信号灯超时时间已到") while the CDN host `https://dl.google.com/dl/android/maven2/`
// serves the identical Maven layout. Gradle 9 pins the URL inside `google()`,
// so the redirect is applied by a Gradle init script instead of here - see
// `app/android/gradle/google-cdn.init.gradle`, which is applied automatically
// through `org.gradle.jvmargs`-independent `GRADLE_OPTS`/init-script wiring
// documented in docs/DEPLOY.md. The hosts file could not be used: it is not
// writable without administrator rights.

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
