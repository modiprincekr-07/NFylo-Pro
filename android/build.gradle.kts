allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.configureEach {
        exclude(group = "com.google.android.play")
        exclude(group = "com.google.android.play", module = "core")
        exclude(group = "com.google.android.play", module = "core-common")
        exclude(group = "com.google.android.play", module = "review")
        exclude(group = "com.google.android.play", module = "app-update")
        exclude(group = "com.google.android.play", module = "feature-delivery")
        exclude(group = "com.google.android.play", module = "integrity")
        exclude(group = "com.google.android.play", module = "asset-delivery")
        
        resolutionStrategy.dependencySubstitution {
            substitute(module("com.google.android.play:core")).using(module("androidx.annotation:annotation:1.9.1"))
            substitute(module("com.google.android.play:core-common")).using(module("androidx.annotation:annotation:1.9.1"))
            substitute(module("com.google.android.play:review")).using(module("androidx.annotation:annotation:1.9.1"))
            substitute(module("com.google.android.play:app-update")).using(module("androidx.annotation:annotation:1.9.1"))
            substitute(module("com.google.android.play:feature-delivery")).using(module("androidx.annotation:annotation:1.9.1"))
            substitute(module("com.google.android.play:integrity")).using(module("androidx.annotation:annotation:1.9.1"))
            substitute(module("com.google.android.play:asset-delivery")).using(module("androidx.annotation:annotation:1.9.1"))
            
            // Drop-in replacement for retired Arthenica FFmpegKit binaries (com.arthenica -> dev.ffmpegkit-maintained)
            substitute(module("com.arthenica:ffmpeg-kit-https")).using(module("dev.ffmpegkit-maintained:ffmpeg-kit-https:6.0.4"))
            substitute(module("com.arthenica:ffmpeg-kit-https:6.0-2")).using(module("dev.ffmpegkit-maintained:ffmpeg-kit-https:6.0.4"))
            substitute(module("com.arthenica:ffmpeg-kit-https:6.0-2.LTS")).using(module("dev.ffmpegkit-maintained:ffmpeg-kit-https:6.0.4"))
            substitute(module("com.arthenica:ffmpeg-kit-full")).using(module("dev.ffmpegkit-maintained:ffmpeg-kit-full:6.0.4"))
            substitute(module("com.arthenica:ffmpeg-kit-min")).using(module("dev.ffmpegkit-maintained:ffmpeg-kit-min:6.0.4"))
            substitute(module("com.arthenica:ffmpeg-kit")).using(module("dev.ffmpegkit-maintained:ffmpeg-kit:6.0.4"))
        }
    }
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core:1.13.1")
            force("androidx.core:core-ktx:1.13.1")
            force("androidx.navigation:navigation-runtime:2.7.7")
            force("androidx.navigation:navigation-common:2.7.7")
            force("androidx.navigation:navigation-ui:2.7.7")
            force("androidx.navigation:navigation-fragment:2.7.7")
            force("androidx.activity:activity:1.9.3")
            force("androidx.activity:activity-ktx:1.9.3")
            force("androidx.savedstate:savedstate:1.2.1")
            force("androidx.savedstate:savedstate-ktx:1.2.1")
            force("androidx.lifecycle:lifecycle-runtime:2.8.7")
            force("androidx.lifecycle:lifecycle-common:2.8.7")
            force("androidx.lifecycle:lifecycle-viewmodel:2.8.7")
            force("androidx.lifecycle:lifecycle-common-java8:2.8.7")
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

subprojects {
    if (project.name != "app") {
        project.afterEvaluate {
            project.plugins.withId("com.android.library") {
                project.extensions.configure<com.android.build.gradle.LibraryExtension> {
                    compileSdk = 35
                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
                    }
                }
            }
            project.tasks.withType<JavaCompile>().configureEach {
                sourceCompatibility = "17"
                targetCompatibility = "17"
            }
            project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

subprojects {
    project.plugins.withId("com.android.library") {
        project.extensions.configure<com.android.build.gradle.LibraryExtension> {
            compileSdk = 35
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
