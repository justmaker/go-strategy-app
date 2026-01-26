#import "KataGoWrapper.h"
#include "katago/cpp/main.h"
#include <iostream>
#include <streambuf>
#include <string>
#include <thread>
#include <unistd.h>
#include <vector>

// --- Stream Buffer Implementation for File Descriptors ---
class FdOutStreambuf : public std::streambuf {
  int fd;

public:
  FdOutStreambuf(int _fd) : fd(_fd) {}

protected:
  int_type overflow(int_type c) override {
    if (c != EOF) {
      char z = c;
      if (write(fd, &z, 1) != 1)
        return EOF;
    }
    return c;
  }
  std::streamsize xsputn(const char *s, std::streamsize n) override {
    return write(fd, s, n);
  }
};

class FdInStreambuf : public std::streambuf {
  int fd;
  char buffer[1];

public:
  FdInStreambuf(int _fd) : fd(_fd) {}

protected:
  int_type underflow() override {
    if (read(fd, buffer, 1) <= 0)
      return EOF;
    setg(buffer, buffer, buffer + 1);
    return traits_type::to_int_type(buffer[0]);
  }
};
// --------------------------------------------------------

static std::thread g_kataGoThread;
static int g_pipeIn[2];
static int g_pipeOut[2];

static std::unique_ptr<FdInStreambuf> g_bufIn;
static std::unique_ptr<FdOutStreambuf> g_bufOut;
static std::unique_ptr<std::istream> g_kpCin;
static std::unique_ptr<std::ostream> g_kpCout;

@implementation KataGoWrapper

+ (BOOL)startWithConfig:(NSString *)configPath model:(NSString *)modelPath {
  if (!configPath || !modelPath)
    return NO;
  std::string cfgStr = [configPath UTF8String];
  std::string modelStr = [modelPath UTF8String];

  NSLog(@"[KataGoWrapper] Starting Native KataGo...");
  if (pipe(g_pipeIn) < 0 || pipe(g_pipeOut) < 0)
    return NO;

  g_bufIn.reset(new FdInStreambuf(g_pipeIn[0]));
  g_bufOut.reset(new FdOutStreambuf(g_pipeOut[1]));

  g_kpCin.reset(new std::istream(g_bufIn.get()));
  g_kpCout.reset(new std::ostream(g_bufOut.get()));

  std::vector<std::string> args;
  args.push_back("katago");
  args.push_back("analysis");
  args.push_back("-config");
  args.push_back(cfgStr);
  args.push_back("-model");
  args.push_back(modelStr);
  // Force specific parameters to reduce memory
  args.push_back("-analysis-threads");
  args.push_back("1");

  g_kataGoThread = std::thread([args]() {
    try {
      MainCmds::analysis(args, *g_kpCin, *g_kpCout);
    } catch (...) {
    }
  });

  g_kataGoThread.detach();
  return YES;
}

+ (void)writeToProcess:(NSString *)data {
  const char *utf8 = [data UTF8String];
  if (!utf8)
    return;
  std::string input(utf8);
  // Manually write to pipeIn[1]
  input += "\n";
  write(g_pipeIn[1], input.c_str(), input.size());
}

+ (NSString *)readFromProcess {
  std::string line;
  char c;
  while (read(g_pipeOut[0], &c, 1) > 0) {
    if (c == '\n')
      break;
    line += c;
  }
  return [NSString stringWithUTF8String:line.c_str()];
}

+ (void)stop {
  close(g_pipeIn[1]);
}

@end
