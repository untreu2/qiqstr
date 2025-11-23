allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val androidExtension = project.extensions.findByName("android")
            if (androidExtension is com.android.build.gradle.BaseExtension) {
                androidExtension.compileSdkVersion = "android-36"
                androidExtension.buildToolsVersion = "36.0.0"
                androidExtension.ndkVersion = "27.0.12077973"
                if (androidExtension.namespace == null) {
                    androidExtension.namespace = project.group.toString()
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.register("fixSqflite") {
        doLast {
            val sqfliteUtilsPath = file("${System.getProperty("user.home")}/.pub-cache/hosted/pub.dev/sqflite_android-2.4.2+2/android/src/main/java/com/tekartik/sqflite/Utils.java")
            if (sqfliteUtilsPath.exists()) {
                var content = sqfliteUtilsPath.readText()
                // Replace BAKLAVA with numeric value 35
                content = content.replace("Build.VERSION_CODES.BAKLAVA", "35")
                sqfliteUtilsPath.writeText(content)
                println("Fixed sqflite BAKLAVA issue")
            }
        }
    }
    
    tasks.whenTaskAdded {
        if (name == "preBuild") {
            dependsOn("fixSqflite")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
