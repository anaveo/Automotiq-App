# Keep Google Play Core classes used for dynamic feature modules
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Flutter and Android support rules
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Keep OkHttp (used by grpc, if you have grpc dependency)
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**

# Keep all protobuf generated classes if you use protobuf
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Keep JavaX annotations
-keep class javax.annotation.** { *; }
-dontwarn javax.annotation.**

# --- MediaPipe Protobuf Keep Rules ---
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# --- JavaPoet / AutoValue (shaded in mediapipe dependencies) ---
-keep class autovalue.shaded.com.squareup.javapoet$.* { *; }
-dontwarn autovalue.shaded.com.squareup.javapoet$.*

# --- javax.lang.model classes (compile-time only, safe to suppress warnings) ---
-dontwarn javax.lang.model.**
-keep class javax.lang.model.** { *; }
