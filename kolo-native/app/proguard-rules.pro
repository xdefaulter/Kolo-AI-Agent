# Add project specific ProGuard rules here.

# Keep model classes for serialization
-keepattributes *Annotation*
-keep class com.kolo.agent.core.model.** { *; }
-keep class kotlinx.serialization.** { *; }

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**