# R8 rules for Kolo AI Agent release builds.
#
# Anything that is accessed by reflection — plugin entrypoints, Firebase
# service classes, Dio JSON converters, native bridges — must be kept
# explicitly. The Flutter tool injects its own baseline rules; these add
# project-specific keeps on top.

# --- Firebase / Google Play Services -------------------------------------
# Crashlytics / Google Mobile Ads / Firebase Core all use reflective
# service discovery under the hood. Keep the public Firebase surface and
# the annotated entries.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics: keep symbols so the stack-trace de-obfuscation mapping
# actually matches what you upload to Firebase.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# --- Flutter / Dart ------------------------------------------------------
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Project-local bridges ----------------------------------------------
# Our accessibility + screenshot services are invoked from the OS by
# name, so R8 must not rename them.
-keep class com.kolo.kolo_ai_agent.KoloAccessibilityService { *; }
-keep class com.kolo.kolo_ai_agent.KoloScreenshotService { *; }
-keep class com.kolo.kolo_ai_agent.MainActivity { *; }

# --- Plugin packages that reflect on runtime handlers --------------------
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.dexterous.** { *; }
-keep class com.yhdev.** { *; }

# --- Kotlin metadata -----------------------------------------------------
# Without this, stack traces show nameless anonymous classes.
-keep class kotlin.Metadata { *; }
-keepclassmembers class ** {
    @kotlin.Metadata <fields>;
    @kotlin.Metadata <methods>;
}

# --- Missing classes (shrinker warnings) --------------------------------
# Firebase pulls javax.lang.model.* through its annotation processors at
# compile time only. The release shrinker sees unresolved references and
# complains; silence the ones we know are safe.
-dontwarn javax.lang.model.**
-dontwarn org.w3c.dom.bootstrap.DOMImplementationRegistry
