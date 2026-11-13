-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

# Stripe Android SDK & 3DS2
-dontwarn com.stripe.android.**
-keep class com.stripe.android.** { *; }
-keepclassmembers class com.stripe.android.** { *; }

# Google Pay / Wallet
-keep class com.google.android.gms.wallet.** { *; }
-dontwarn com.google.android.gms.wallet.**

# Firebase / Play Core / Flutter JNI
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.firebase.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
