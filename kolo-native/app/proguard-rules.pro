# Add project specific ProGuard rules here.

# Kotlin serialization and API/domain models.
-keepattributes *Annotation*
-keepattributes Signature
-keep class com.kolo.agent.core.model.** { *; }
-keep class com.kolo.agent.core.model.api.** { *; }
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class **$$serializer { *; }
-keepclassmembers class **$Companion { *; }

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-keep @androidx.room.Dao class *
-keep class com.kolo.agent.core.database.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Tink references compile-time Error Prone annotations that are not packaged at runtime.
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi

# Hilt/Dagger generated code.
-dontwarn dagger.hilt.**
-dontwarn javax.annotation.**
-keep class dagger.hilt.** { *; }
-keep class hilt_aggregated_deps.** { *; }
-keep class *_HiltModules_* { *; }

# Accessibility service and native bridge entry points.
-keep class com.kolo.agent.feature.phonecontrol.service.PhoneControlAccessibilityService { *; }
-keep class com.kolo.agent.core.providers.local.LlamaCppEngine { *; }
-keep class com.kolo.agent.core.providers.local.LlamaTokenCallback { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
