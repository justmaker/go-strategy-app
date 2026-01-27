Pod::Spec.new do |s|
  s.name             = 'KataGoMobile'
  s.version          = '0.0.1'
  s.summary          = 'KataGo Native Engine for iOS'
  s.description      = <<-DESC
This pod encapsulates the KataGo Go engine code for local execution on iOS devices.
                       DESC
  s.homepage         = 'https://github.com/lightvector/KataGo'
  s.license          = { :type => 'MIT', :file => 'Sources/katago/LICENSE' }
  s.author           = { 'Rex Hsu' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = [
    'Sources/*.{h,mm,cpp}',
    'Sources/katago/cpp/**/*.{h,cpp}'
  ]
  s.public_header_files = 'Sources/KataGoWrapper.h'
  s.libraries = 'z'
  
  # Exclude non-ios backends and tests
  s.exclude_files = [
    'Sources/katago/cpp/main.cpp',
    'Sources/katago/cpp/tests/**/*',
    'Sources/katago/cpp/neuralnet/opencl*',
    'Sources/katago/cpp/neuralnet/cuda*',
    'Sources/katago/cpp/neuralnet/tensorrt*',
    'Sources/katago/cpp/distributed/**/*',
    'Sources/katago/cpp/command/benchmark.cpp',
    'Sources/katago/cpp/command/contribute.cpp',
    'Sources/katago/cpp/command/demoplay.cpp',
    'Sources/katago/cpp/command/evalsgf.cpp',
    'Sources/katago/cpp/command/gatekeeper.cpp',
    'Sources/katago/cpp/command/genbook.cpp',
    'Sources/katago/cpp/command/gputest.cpp',
    'Sources/katago/cpp/command/match.cpp',
    'Sources/katago/cpp/command/misc.cpp',
    'Sources/katago/cpp/command/runtests.cpp',
    'Sources/katago/cpp/command/sandbox.cpp',
    'Sources/katago/cpp/command/selfplay.cpp',
    'Sources/katago/cpp/command/startposes.cpp',
    'Sources/katago/cpp/command/tune.cpp',
    'Sources/katago/cpp/command/writetrainingdata.cpp'
  ]

  s.ios.deployment_target = '13.0'
  

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'USE_BACKEND_EIGEN=1 NO_GIT_REVISION=1',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Sources/eigen" "$(PODS_TARGET_SRCROOT)/Sources/katago/cpp" "$(PODS_TARGET_SRCROOT)/Sources/katago/cpp/external" "$(PODS_TARGET_SRCROOT)/Sources/katago/cpp/external/tclap-1.2.5/include" "$(PODS_TARGET_SRCROOT)/Sources/katago/cpp/external/nlohmann_json" "$(PODS_TARGET_SRCROOT)/Sources/katago/cpp/external/filesystem-1.5.8/include" "$(PODS_TARGET_SRCROOT)/Sources/fake_zip"'
  }
end
