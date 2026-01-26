#include <android/log.h>
#include <ext/stdio_filebuf.h> // GCC/Clang extension for filebuf from fd
#include <iostream>
#include <jni.h>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

// Include KataGo Main Headers
#include "katago/cpp/main.h"

#define TAG "KataGoNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Global state
static std::thread g_kataGoThread;
static int g_pipeIn[2];  // Java -> KataGo
static int g_pipeOut[2]; // KataGo -> Java

static std::unique_ptr<__gnu_cxx::stdio_filebuf<char>> g_bufIn;
static std::unique_ptr<__gnu_cxx::stdio_filebuf<char>> g_bufOut;
static std::unique_ptr<std::istream> g_kpCin;
static std::unique_ptr<std::ostream> g_kpCout;

extern "C" JNIEXPORT jboolean JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_startNative(
    JNIEnv *env, jobject thiz, jstring configPath, jstring modelPath) {

  const char *cfg = env->GetStringUTFChars(configPath, nullptr);
  const char *model = env->GetStringUTFChars(modelPath, nullptr);

  std::string cfgStr(cfg);
  std::string modelStr(model);

  env->ReleaseStringUTFChars(configPath, cfg);
  env->ReleaseStringUTFChars(modelPath, model);

  LOGI("Initializing Native KataGo...");
  LOGI("Config: %s", cfgStr.c_str());
  LOGI("Model: %s", modelStr.c_str());

  // Create Pipes
  if (pipe(g_pipeIn) < 0 || pipe(g_pipeOut) < 0) {
    LOGE("Failed to create pipes");
    return JNI_FALSE;
  }

  // Wrap pipes in streams
  // g_pipeIn[0] is read end (for KataGo)
  // g_pipeOut[1] is write end (for KataGo)
  g_bufIn.reset(new __gnu_cxx::stdio_filebuf<char>(g_pipeIn[0], std::ios::in));
  g_bufOut.reset(
      new __gnu_cxx::stdio_filebuf<char>(g_pipeOut[1], std::ios::out));

  g_kpCin.reset(new std::istream(g_bufIn.get()));
  g_kpCout.reset(new std::ostream(g_bufOut.get()));

  // Prepare Args
  // argv[0] is program name
  std::vector<std::string> args;
  args.push_back("katago");
  args.push_back("analysis");
  args.push_back("-config");
  args.push_back(cfgStr);
  args.push_back("-model");
  args.push_back(modelStr);

  // Launch Thread
  g_kataGoThread = std::thread([args]() {
    LOGI("KataGo Thread Started");
    // We call analysis(args, in, out)
    // Note: MainCmds::analysis must be modified to accept streams!
    // We assume we did that modification.
    try {
      MainCmds::analysis(args, *g_kpCin, *g_kpCout);
    } catch (const std::exception &e) {
      LOGE("KataGo Exception: %s", e.what());
    } catch (...) {
      LOGE("KataGo Unknown Exception");
    }
    LOGI("KataGo Thread Ended");
  });

  // Detach to let it run
  g_kataGoThread.detach();

  return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_writeToProcess(
    JNIEnv *env, jobject thiz, jstring data) {

  const char *str = env->GetStringUTFChars(data, nullptr);
  std::string input(str);
  env->ReleaseStringUTFChars(data, str);

  // Write to g_pipeIn[1]
  input += "\n"; // Ensure newline
  write(g_pipeIn[1], input.c_str(), input.size());
  // No flush needed for unbuffered pipe write usually, but maybe?
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_readFromProcess(
    JNIEnv *env, jobject thiz) {

  // Read from g_pipeOut[0]
  // Blocking read?
  // We should read line by line.

  // Simplest: Read one char at a time until newline to construct a line?
  // Or use a FILE* or fdopen?

  // Let's use low-level read loop to get a line.
  std::string line;
  char c;
  while (read(g_pipeOut[0], &c, 1) > 0) {
    if (c == '\n')
      break;
    line += c;
  }

  return env->NewStringUTF(line.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_stopNative(JNIEnv *env,
                                                              jobject thiz) {
  // Write quit command logic handled by Java sending "quit" json?
  // Or we close pipes.
  close(g_pipeIn[1]); // Close write end, KataGo sees EOF
                      // Wait for thread? It detached.
                      // Cleanup
}
