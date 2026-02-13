#include <android/log.h>
#include <iostream>
#include <jni.h>
#include <memory>
#include <streambuf>
#include <string>
#include <pthread.h>
#include <unistd.h>
#include <vector>

// Include KataGo Main Headers
#include "katago/cpp/main.h"

#define TAG "KataGoNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// Custom streambuf for reading from a file descriptor
class fdinbuf : public std::streambuf {
protected:
  int fd;
  char buffer[1];

public:
  fdinbuf(int _fd) : fd(_fd) { setg(buffer, buffer, buffer); }

protected:
  virtual int_type underflow() override {
    if (gptr() < egptr()) {
      return traits_type::to_int_type(*gptr());
    }
    ssize_t n = read(fd, buffer, 1);
    if (n <= 0) {
      return traits_type::eof();
    }
    setg(buffer, buffer, buffer + 1);
    return traits_type::to_int_type(*gptr());
  }
};

// Custom streambuf for writing to a file descriptor
class fdoutbuf : public std::streambuf {
protected:
  int fd;

public:
  fdoutbuf(int _fd) : fd(_fd) {}

protected:
  virtual int_type overflow(int_type c) override {
    if (c != traits_type::eof()) {
      char z = static_cast<char>(c);
      if (write(fd, &z, 1) != 1) {
        return traits_type::eof();
      }
    }
    return c;
  }
  virtual std::streamsize xsputn(const char *s, std::streamsize n) override {
    return (std::streamsize)write(fd, s, (size_t)n);
  }
};

// Thread data structure to pass args to pthread
struct KataGoThreadData {
  std::vector<std::string> args;
};

// Global state
static pthread_t g_kataGoThread;
static int g_pipeIn[2];  // Java -> KataGo
static int g_pipeOut[2]; // KataGo -> Java

static std::unique_ptr<fdinbuf> g_bufIn;
static std::unique_ptr<fdoutbuf> g_bufOut;
static std::unique_ptr<std::istream> g_kpCin;
static std::unique_ptr<std::ostream> g_kpCout;

// pthread worker function
static void* kataGoThreadFunc(void* arg) {
  KataGoThreadData* data = static_cast<KataGoThreadData*>(arg);
  LOGI("KataGo pthread started");

  try {
    MainCmds::analysis(data->args, *g_kpCin, *g_kpCout);
  } catch (const std::exception &e) {
    LOGE("KataGo Exception: %s", e.what());
  } catch (...) {
    LOGE("KataGo Unknown Exception");
  }

  delete data;
  LOGI("KataGo pthread ended");
  return nullptr;
}

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
  g_bufIn = std::make_unique<fdinbuf>(g_pipeIn[0]);
  g_bufOut = std::make_unique<fdoutbuf>(g_pipeOut[1]);

  g_kpCin = std::make_unique<std::istream>(g_bufIn.get());
  g_kpCout = std::make_unique<std::ostream>(g_bufOut.get());

  // Prepare Args
  // argv[0] is program name
  KataGoThreadData* threadData = new KataGoThreadData();
  threadData->args.push_back("katago");
  threadData->args.push_back("analysis");
  threadData->args.push_back("-config");
  threadData->args.push_back(cfgStr);
  threadData->args.push_back("-model");
  threadData->args.push_back(modelStr);

  // Create pthread with increased stack size for KataGo's heavy computation
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

  // Set large stack size (4MB) to avoid JNI issues on Android
  // Default stack may be insufficient for KataGo + JNI calls
  size_t stackSize = 4 * 1024 * 1024; // 4MB
  pthread_attr_setstacksize(&attr, stackSize);
  LOGI("Creating pthread with stack size: %zu bytes", stackSize);

  int ret = pthread_create(&g_kataGoThread, &attr, kataGoThreadFunc, threadData);
  pthread_attr_destroy(&attr);

  if (ret != 0) {
    LOGE("Failed to create pthread: %d", ret);
    delete threadData;
    return JNI_FALSE;
  }

  LOGI("KataGo pthread created successfully");
  return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_writeToProcess(
    JNIEnv *env, jobject thiz, jstring data) {

  const char *str = env->GetStringUTFChars(data, nullptr);
  if (!str)
    return;
  std::string input(str);
  env->ReleaseStringUTFChars(data, str);

  // Write to g_pipeIn[1]
  input += "\n"; // Ensure newline
  write(g_pipeIn[1], input.c_str(), input.size());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_readFromProcess(
    JNIEnv *env, jobject thiz) {

  // Read from g_pipeOut[0]
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
  close(g_pipeIn[1]); // Close write end, KataGo sees EOF
}

// JNI_OnLoad: Called when library is loaded
// Initialize resources early to avoid static initialization issues
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
  LOGI("JNI_OnLoad called - early initialization");
  return JNI_VERSION_1_6;
}
