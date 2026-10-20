import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Keep Robolectric's test platform under Gradle checksum verification too;
// tests never download an unpinned Android runtime behind Gradle's back.
val robolectricSdk by configurations.creating
val prepareRobolectricSdk by tasks.registering(Sync::class) {
    from(robolectricSdk)
    into(layout.buildDirectory.dir("robolectric-sdk"))
}

android {
    namespace = "dev.ian.ble"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.ian.ble"
        minSdk = 31
        targetSdk = 36
        versionCode = 7
        versionName = "0.3.3"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    signingConfigs {
        getByName("debug") {
            // Development only: keep this outside ephemeral ~/.android and out of Git/Nix.
            storeFile = file("../../.local/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    buildTypes {
        release { isMinifyEnabled = false }
    }
    testOptions.unitTests {
        isIncludeAndroidResources = true
        all {
            it.dependsOn(prepareRobolectricSdk)
            it.systemProperty("robolectric.offline", "true")
            it.systemProperty("robolectric.dependency.dir", layout.buildDirectory.dir("robolectric-sdk").get().asFile.path)
        }
    }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    implementation("androidx.activity:activity:1.11.0")
    implementation("com.google.android.gms:play-services-auth:22.0.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
    testImplementation("org.robolectric:robolectric:4.14.1")
    robolectricSdk("org.robolectric:android-all-instrumented:15-robolectric-12650502-i7")
}
