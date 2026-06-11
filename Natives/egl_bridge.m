#import "SurfaceViewController.h"

#include "jni.h"
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"

int clientAPI;

void JNI_LWJGL_changeRenderer(const char* value_c) {
    JNIEnv *env;
    (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);
    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");
    jstring value = (*env)->NewStringUTF(env, value_c);
    jclass clazz = (*env)->FindClass(env, "java/lang/System");
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
}

void pojavTerminate() {
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pojavGetCurrentContext() {
    return br_get_current();
}

int pojavInit(BOOL useStackQueue) {
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    isUseStackQueueCall = useStackQueue;
    return JNI_TRUE;
}

int pojavInitOpenGL() {
    NSString *renderer = NSProcessInfo.processInfo.environment[@"POJAV_RENDERER"];
    BOOL isAuto = [renderer isEqualToString:@"auto"];
    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // At this point, if renderer is still auto (unspecified major version), pick gl4es
        renderer = @ RENDERER_NAME_GL4ES;
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_NG_GL4ES]) {
        renderer = @ RENDERER_NAME_NG_GL4ES;
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
        // NG-GL4ES constructor calls glGetString(GL_EXTENSIONS) which needs a valid
        // current GL context. Initialize EGL first, then create a temp context
        // and make it current BEFORE dlopen to prevent SIGSEGV in GetHardwareExtensions.
        // Also set LIBGL_EGL/LIBGL_GLES so NG-GL4ES can find our ANGLE implementation
        // via dlsym(RTLD_DEFAULT, ...) instead of failing with RTLD_NEXT.
        setenv("LIBGL_EGL", "@rpath/libtinygl4angle.dylib", 1);
        setenv("LIBGL_GLES", "@rpath/libtinygl4angle.dylib", 1);
        BOOL ngInitOk = NO;
        if (!br_init()) {
            NSLog(@"[EGL Bridge] Failed to initialize EGL display for NG-GL4ES");
        } else {
            basic_render_window_t *tmpCtx = br_init_context(NULL);
            if (tmpCtx) {
                br_make_current(tmpCtx);
                ngInitOk = YES;
            } else {
                NSLog(@"[EGL Bridge] Warning: Could not create temp context for NG-GL4ES, extension query may fail");
            }
        }
        JNI_LWJGL_changeRenderer(renderer.UTF8String);
        dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);
        return ngInitOk ? 0 : 1;
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_VK_ZINK]) {
        setenv("GALLIUM_DRIVER","zink",1);
        set_osm_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_VULKAN]) {
        // Vulkan renderer: pure Vulkan path via MoltenVK.
        // No GL bridge needed - game uses Vulkan API directly through MoltenVK.
        // When clientAPI == GLFW_NO_API, pojavCreateContext returns the Metal layer.
        NSLog(@"[EGL Bridge] Vulkan renderer selected, pure MoltenVK path (no GL fallback)");
        setenv("GALLIUM_DRIVER", "", 1);
        // Skip all GL init: no bridge table, no dlopen, no br_init.
        return 0;
    } else {
        NSLog(@"[EGL Bridge] Unknown renderer '%@', falling back to %@", renderer, @ RENDERER_NAME_GL4ES);
        renderer = @ RENDERER_NAME_GL4ES;
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    }
    JNI_LWJGL_changeRenderer(renderer.UTF8String);
    // Preload renderer library
    dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);

    return !br_init();
    //return 0;
}

void pojavSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
    } else if (strcmp(getenv("POJAV_RENDERER"), "auto")==0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                setenv("POJAV_RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;
            // case 4: use Zink?
            default:
                setenv("POJAV_RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pojavSwapBuffers() {
    br_swap_buffers();
}

void pojavMakeCurrent(basic_render_window_t* window) {
    br_make_current(window);
}

void* pojavCreateContext(basic_render_window_t* contextSrc) {
    // Always initialize OpenGL bridge first, even for Vulkan path,
    // because some games/mods still call GL.createCapabilities()
    static BOOL inited = NO;
    if (!inited) {
        inited = YES;
        pojavInitOpenGL();
    }

    if (clientAPI == GLFW_NO_API) {
        // Game has selected Vulkan API to render
        NSLog(@"[EGL Bridge] Vulkan API selected, returning Metal layer for MoltenVK");
        // Configure MoltenVK for A11 GPU (iPhone 8 Plus / iPhone X)
        // A11 has a tri-core Apple GPU - optimize Metal command handling
        setenv("MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS", "1", 1);
        setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "0", 1);
        setenv("MVK_CONFIG_USE_METAL_PRIVATE_CLASSES", "0", 1);
        setenv("MVK_CONFIG_USE_COMMAND_POOLING", "1", 1);
        setenv("MVK_CONFIG_USE_MTLHEAP", "0", 1);
        setenv("MVK_CONFIG_FAST_MATH_ENABLED", "1", 1);
        setenv("MVK_CONFIG_SPECIALIZED_QUEUE_FAMILIES", "1", 1);
        setenv("MVK_CONFIG_SWAPCHAIN_MAG_FILTER_USE_NEAREST", "1", 1);
        // iOS 16.7.16 compatibility: disable Metal private classes for A11
        // to prevent crashes on older iOS versions
        setenv("MVK_CONFIG_LOG_LEVEL", "0", 1);
        NSLog(@"[EGL Bridge] MoltenVK configured for A11 GPU + iOS 16.7.16");
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    return br_init_context(contextSrc);
}

void pojavSwapInterval(int interval) {
    if (!br_swap_interval) return;
    br_swap_interval(interval);
}
