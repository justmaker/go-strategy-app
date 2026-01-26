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
    'Sources/**/*.{h,cpp,mm,hpp}',
    'Sources/katago/cpp/**/*.{h,cpp}',
    'Sources/katago/cpp/external/**/*.{h,cpp}'
  ]
  s.public_header_files = 'Sources/KataGoWrapper.h'
  
  # Exclude non-ios backends and tests
  s.exclude_files = [
    'Sources/katago/cpp/main.cpp',
    'Sources/katago/cpp/tests/**/*',
    'Sources/katago/cpp/neuralnet/opencl*',
    'Sources/katago/cpp/neuralnet/cuda*',
    'Sources/katago/cpp/neuralnet/tensorrt*',
    'Sources/katago/cpp/command/checksgf.cpp'
  ]

  s.ios.deployment_target = '13.0'
  
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'USE_BACKEND_EIGEN=1 NO_GIT_REVISION=1',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Sources/eigen" "${PODS_TARGET_SRCROOT}/Sources/katago/cpp" "${PODS_TARGET_SRCROOT}/Sources/katago/cpp/external"'
  }
end
