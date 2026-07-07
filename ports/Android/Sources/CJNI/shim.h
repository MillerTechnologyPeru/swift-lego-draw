// Raw JNI + NDK logging, straight from the Android NDK sysroot bundled with the Swift Android
// SDK. Deliberately avoids any higher-level Swift JNI wrapper package: the JNI C ABI is a stable,
// well-documented spec, so calling it directly here keeps this test harness's dependency graph
// to just this repo's own package.
#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
