pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "kolo-native"

include(":app")
include(":core:model")
include(":core:database")
include(":core:providers")
include(":core:agent")
include(":core:tools")
include(":feature:chat")
include(":feature:settings")
include(":feature:phonecontrol")