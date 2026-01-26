#include <android/log.h>
#include <iostream>
#include <jni.h>
#include <memory>
#include <streambuf>
#include <string>
#include <thread>
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
    return write(fd, s, n);
  }
};

// Global state
static std::thread g_kataGoThread;
static int g_pipeIn[2];  // Java -> KataGo
static int g_pipeOut[2]; // KataGo -> Java

static std::unique_ptr<fdinbuf> g_bufIn;
static std::unique_ptr<fdoutbuf> g_bufOut;
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
  g_bufIn = std::make_unique<fdinbuf>(g_pipeIn[0]);
  g_bufOut = std::make_unique<fdoutbuf>(g_pipeOut[1]);

  g_kpCin = std::make_unique<std::istream>(g_bufIn.get());
  g_kpCout = std::make_unique<std::ostream>(g_bufOut.get());

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
