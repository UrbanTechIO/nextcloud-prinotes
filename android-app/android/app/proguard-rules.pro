# flutter_local_notifications stores its scheduled notifications with Gson and reads them back from the
# boot / alarm receivers. Gson needs the generic type information, which R8 removes by default; without
# these rules the receiver crashes with "TypeToken must be created with a type argument".
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ML Kit text recognition: the plugin references the optional language packs we do not bundle (Latin only).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
