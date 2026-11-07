# flutter_local_notifications stores its scheduled notifications with Gson and reads them back from the
# boot / alarm receivers. Gson needs the generic type information, which R8 removes by default; without
# these rules the receiver crashes with "TypeToken must be created with a type argument".
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
