#include <jni.h>
#include <string>
#include <android/log.h>

#define TAG "KataGoNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

extern "C" JNIEXPORT jstring JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_stringFromJNI(
        JNIEnv* env,
        jobject /* this */) {
    std::string hello = "Hello from Native C++ (KataGo Stub)";
    LOGI("Native interface called");
    return env->NewStringUTF(hello.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_startNative(
        JNIEnv* env,
        jobject /* this */) {
    LOGI("Starting KataGo native engine...");
    // TODO: Initialize actual KataGo instance
    return JNI_TRUE;
}
