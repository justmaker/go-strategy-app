# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in /Users/flutter/apps/flutter/packages/flutter_tools/gradle/flutter_proguard_rules.pro
# as well as the default proguard-android-optimize.txt.

# Keep method names for native methods (required for JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}
