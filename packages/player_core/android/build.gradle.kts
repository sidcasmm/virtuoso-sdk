group = "com.virtuoso.player.player_core"
version = "1.0.0"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.virtuoso.player.player_core"
    compileSdk = 36
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    api(files("libs/player_core.aar"))
    api("androidx.media3:media3-exoplayer:1.6.1")
    api("androidx.media3:media3-exoplayer-hls:1.6.1")
    api("androidx.media3:media3-exoplayer-dash:1.6.1")
    api("androidx.media3:media3-database:1.6.1")
    api("androidx.media3:media3-session:1.6.1")
    api("androidx.lifecycle:lifecycle-common:2.8.7")
}
