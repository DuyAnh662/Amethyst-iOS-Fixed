#import <Foundation/Foundation.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include <pthread.h>
#include "bridge_tbl.h"
#include "environ.h"
#include "gl_bridge.h"
#include "utils.h"

static EGLDisplay g_EglDisplay;
static egl_library handle;
static gl_render_window_t* lastCreatedContext;
static void* g_angleHandle;

void dlsym_EGL() {
    g_angleHandle = dlopen("@rpath/libtinygl4angle.dylib", RTLD_GLOBAL);
    assert(g_angleHandle);
    handle.eglBindAPI = dlsym(g_angleHandle, "eglBindAPI");
    handle.eglChooseConfig = dlsym(g_angleHandle, "eglChooseConfig");
    handle.eglCreateContext = dlsym(g_angleHandle, "eglCreateContext");
    handle.eglCreateWindowSurface = dlsym(g_angleHandle, "eglCreateWindowSurface");
    handle.eglCreatePbufferSurface = dlsym(g_angleHandle, "eglCreatePbufferSurface");
    handle.eglDestroyContext = dlsym(g_angleHandle, "eglDestroyContext");
    handle.eglDestroySurface = dlsym(g_angleHandle, "eglDestroySurface");
    handle.eglGetConfigAttrib = dlsym(g_angleHandle, "eglGetConfigAttrib");
    handle.eglGetCurrentContext = dlsym(g_angleHandle, "eglGetCurrentContext");
    handle.eglGetDisplay = dlsym(g_angleHandle, "eglGetDisplay");
    handle.eglGetError = dlsym(g_angleHandle, "eglGetError");
    handle.eglGetPlatformDisplay = dlsym(g_angleHandle, "eglGetPlatformDisplay");
    handle.eglInitialize = dlsym(g_angleHandle, "eglInitialize");
    handle.eglMakeCurrent = dlsym(g_angleHandle, "eglMakeCurrent");
    handle.eglSwapBuffers = dlsym(g_angleHandle, "eglSwapBuffers");
    handle.glGetErrorClear = dlsym(g_angleHandle, "glGetError");
    handle.eglReleaseThread = dlsym(g_angleHandle, "eglReleaseThread");
    handle.eglSwapInterval = dlsym(g_angleHandle, "eglSwapInterval");
    handle.eglTerminate = dlsym(g_angleHandle, "eglTerminate");
    handle.eglGetCurrentSurface = dlsym(g_angleHandle, "eglGetCurrentSurface");
}

static void* dlsym_or_skip(void* lib, const char* name, void* fallback) {
    void* sym = dlsym(lib, name);
    return sym ? sym : fallback;
}

void gl_set_last_created_context(gl_render_window_t* ctx) {
    lastCreatedContext = ctx;
}

void gl_make_current(gl_render_window_t* bundle);

void* gl_get_current_context(void) {
    if (currentBundle == NULL && lastCreatedContext != NULL) {
        // No context current on this thread, but we have a last-created context.
        // This can happen when LWJGL calls GL.createCapabilities() on the render
        // thread while the context was created and bound on the launcher thread.
        // Auto-bind the last created context to this thread (same approach as
        // Android's fixPojavGLContext() workaround).
        NSLog(@"EGLBridge: auto-binding lastCreatedContext=%p on thread %p",
              lastCreatedContext, pthread_self());
        gl_make_current(lastCreatedContext);
    }
    return currentBundle;
}

void gl_redispatch(void* lib) {
    if (!lib) lib = RTLD_DEFAULT;
    handle.eglBindAPI = dlsym_or_skip(lib, "eglBindAPI", handle.eglBindAPI);
    handle.eglChooseConfig = dlsym_or_skip(lib, "eglChooseConfig", handle.eglChooseConfig);
    handle.eglCreateContext = dlsym_or_skip(lib, "eglCreateContext", handle.eglCreateContext);
    handle.eglCreateWindowSurface = dlsym_or_skip(lib, "eglCreateWindowSurface", handle.eglCreateWindowSurface);
    handle.eglCreatePbufferSurface = dlsym_or_skip(lib, "eglCreatePbufferSurface", handle.eglCreatePbufferSurface);
    handle.eglDestroyContext = dlsym_or_skip(lib, "eglDestroyContext", handle.eglDestroyContext);
    handle.eglDestroySurface = dlsym_or_skip(lib, "eglDestroySurface", handle.eglDestroySurface);
    handle.eglGetConfigAttrib = dlsym_or_skip(lib, "eglGetConfigAttrib", handle.eglGetConfigAttrib);
    handle.eglGetCurrentContext = dlsym_or_skip(lib, "eglGetCurrentContext", handle.eglGetCurrentContext);
    handle.eglGetDisplay = dlsym_or_skip(lib, "eglGetDisplay", handle.eglGetDisplay);
    handle.eglGetError = dlsym_or_skip(lib, "eglGetError", handle.eglGetError);
    handle.eglGetPlatformDisplay = dlsym_or_skip(lib, "eglGetPlatformDisplay", handle.eglGetPlatformDisplay);
    handle.eglInitialize = dlsym_or_skip(lib, "eglInitialize", handle.eglInitialize);
    handle.eglMakeCurrent = dlsym_or_skip(lib, "eglMakeCurrent", handle.eglMakeCurrent);
    handle.eglSwapBuffers = dlsym_or_skip(lib, "eglSwapBuffers", handle.eglSwapBuffers);
    handle.glGetErrorClear = dlsym_or_skip(lib, "glGetError", handle.glGetErrorClear);
    handle.eglReleaseThread = dlsym_or_skip(lib, "eglReleaseThread", handle.eglReleaseThread);
    handle.eglSwapInterval = dlsym_or_skip(lib, "eglSwapInterval", handle.eglSwapInterval);
    handle.eglTerminate = dlsym_or_skip(lib, "eglTerminate", handle.eglTerminate);
    handle.eglGetCurrentSurface = dlsym_or_skip(lib, "eglGetCurrentSurface", handle.eglGetCurrentSurface);
}

static bool gl_init() {
    dlsym_EGL();

    g_EglDisplay = handle.eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_EglDisplay == EGL_NO_DISPLAY) {
        NSDebugLog(@"EGLBridge: eglGetDisplay(EGL_DEFAULT_DISPLAY) returned EGL_NO_DISPLAY");
        return false;
    }
    if (!handle.eglInitialize(g_EglDisplay, NULL, NULL)) {
        NSDebugLog(@"EGLBridge: Error eglInitialize() failed: 0x%x", handle.eglGetError());
        return false;
    }
    return true;
}

static bool gl_ensure_display_initialized() {
    EGLint major, minor;
    if (handle.eglInitialize(g_EglDisplay, &major, &minor)) {
        return true;
    }
    // Display was terminated (likely by NG-GL4ES constructor during dlopen).
    // Re-establish EGL connection from scratch.
    g_EglDisplay = handle.eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_EglDisplay == EGL_NO_DISPLAY) return false;
    return handle.eglInitialize(g_EglDisplay, &major, &minor);
}

gl_render_window_t* gl_init_context(gl_render_window_t *share) {
    gl_render_window_t* bundle = calloc(1, sizeof(gl_render_window_t));

    if (!gl_ensure_display_initialized()) {
        NSLog(@"EGLBridge: Failed to (re)initialize EGL display");
        free(bundle);
        return NULL;
    }

    NSString *renderer = NSProcessInfo.processInfo.environment[@"POJAV_RENDERER"];
    BOOL useDesktopGL = [renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]
                     || [renderer isEqualToString:@ RENDERER_NAME_NG_GL4ES];

    const EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT|EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, useDesktopGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };

    EGLint num_configs;
    EGLint vid;
    if (!handle.eglChooseConfig(g_EglDisplay, attribs, &bundle->config, 1, &num_configs)) {
        NSDebugLog(@"EGLBridge: Error couldn't get an EGL visual config: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    assert(bundle->config);
    assert(num_configs > 0);

    if (!handle.eglGetConfigAttrib(g_EglDisplay, bundle->config, EGL_NATIVE_VISUAL_ID, &vid)) {
        NSDebugLog(@"EGLBridge: Error eglGetConfigAttrib() failed: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    EGLBoolean bindResult;
    if (useDesktopGL) {
        NSDebugLog(@"EGLBridge: Binding to desktop OpenGL");
        bindResult = handle.eglBindAPI(EGL_OPENGL_API);
    } else {
        NSDebugLog(@"EGLBridge: Binding to OpenGL ES");
        bindResult = handle.eglBindAPI(EGL_OPENGL_ES_API);
    }
    if (!bindResult) NSDebugLog(@"EGLBridge: bind failed: %p\n", handle.eglGetError());

    bundle->surface = handle.eglCreateWindowSurface(g_EglDisplay, bundle->config, (__bridge EGLNativeWindowType)SurfaceViewController.surface.layer, NULL);
    if (!bundle->surface) {
        NSDebugLog(@"EGLBridge: eglCreateWindowSurface finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    const EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    bundle->context = handle.eglCreateContext(g_EglDisplay, bundle->config, share ? share->context : EGL_NO_CONTEXT, ctx_attribs);
    if (!bundle->context) {
        NSDebugLog(@"EGLBridge: Error eglCreateContext finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    //NSDebugLog(@"EGLBridge: Created CTX pointer = %p (source = %p)", bundle->context, share?share->context:0);

    return bundle;
}

void gl_make_current(gl_render_window_t* bundle) {
    if(!bundle) {
        if(handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)) {
            currentBundle = NULL;
            NSLog(@"EGLBridge: unbound context on thread %p", pthread_self());
        }
        return;
    }

    NSLog(@"EGLBridge: making context current on thread %p, display=%p surface=%p context=%p",
          pthread_self(), g_EglDisplay, bundle->surface, bundle->context);
    if(handle.eglMakeCurrent(g_EglDisplay, bundle->surface, bundle->surface, bundle->context)) {
        currentBundle = (basic_render_window_t *)bundle;
        NSLog(@"EGLBridge: context bound OK, currentBundle=%p", currentBundle);
        // Clear any stale GL errors left from NG-GL4ES init (GetHardwareExtensions)
        // to prevent LWJGL's GL.createCapabilities() from rejecting the context.
        if (handle.glGetErrorClear) {
            while (handle.glGetErrorClear() != 0);
        }
        // Debug: compare glGetString from different sources
        typedef const unsigned char* (*glGetString_t)(unsigned int);
        glGetString_t glGetStringD = dlsym(RTLD_DEFAULT, "glGetString");
        if (glGetStringD) {
            const unsigned char* ver = glGetStringD(0x1F02);
            NSLog(@"EGLBridge: glGetString(GL_VERSION) via RTLD_DEFAULT = %s", ver ? ver : "NULL");
        }
        if (g_angleHandle) {
            glGetString_t glGetStringA = dlsym(g_angleHandle, "glGetString");
            if (glGetStringA) {
                const unsigned char* ver = glGetStringA(0x1F02);
                NSLog(@"EGLBridge: glGetString(GL_VERSION) via dlsym(ANGLE) = %s", ver ? ver : "NULL");
            } else {
                NSLog(@"EGLBridge: dlsym(ANGLE, glGetString) = NULL");
            }
            // Also test eglGetProcAddress
            typedef void* (*eglGetProcAddr_t)(const char*);
            eglGetProcAddr_t eglGetProcAddr = dlsym(g_angleHandle, "eglGetProcAddress");
            if (eglGetProcAddr) {
                glGetString_t glGetStringE = eglGetProcAddr("glGetString");
                if (glGetStringE) {
                    const unsigned char* ver = glGetStringE(0x1F02);
                    NSLog(@"EGLBridge: glGetString(GL_VERSION) via eglGetProcAddress = %s", ver ? ver : "NULL");
                } else {
                    NSLog(@"EGLBridge: eglGetProcAddress(glGetString) = NULL");
                }
            } else {
                NSLog(@"EGLBridge: dlsym(ANGLE, eglGetProcAddress) = NULL");
            }
        }
        // Also test eglGetCurrentContext from the renderer
        void* eglCtx = dlsym(RTLD_DEFAULT, "eglGetCurrentContext");
        if (eglCtx) {
            void* (*eglGetCurCtx)(void) = eglCtx;
            void* curCtx = eglGetCurCtx();
            NSLog(@"EGLBridge: eglGetCurrentContext via RTLD_DEFAULT = %p", curCtx);
        }
        // Log our handle.eglGetCurrentContext result too
        if (handle.eglGetCurrentContext) {
            void* curCtx = handle.eglGetCurrentContext();
            NSLog(@"EGLBridge: handle.eglGetCurrentContext = %p", curCtx);
        }
    } else {
        NSLog(@"EGLBridge: eglMakeCurrent returned with error: 0x%x", handle.eglGetError());
    }
}

void gl_swap_buffers() {
    if (!handle.eglSwapBuffers(g_EglDisplay, currentBundle->gl.surface) && handle.eglGetError() == EGL_BAD_SURFACE) {
        NSLog(@"eglSwapBuffers error 0x%x", handle.eglGetError());
        //stopSwapBuffers = true;
        //closeGLFWWindow();
    }
}

gl_render_window_t* gl_init_pbuffer_context() {
    gl_render_window_t* bundle = calloc(1, sizeof(gl_render_window_t));

    if (!gl_ensure_display_initialized()) {
        NSLog(@"EGLBridge: Failed to (re)initialize EGL display for PBuffer");
        free(bundle);
        return NULL;
    }

    NSString *renderer = NSProcessInfo.processInfo.environment[@"POJAV_RENDERER"];
    BOOL useDesktopGL = [renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]
                     || [renderer isEqualToString:@ RENDERER_NAME_NG_GL4ES];

    const EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, useDesktopGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };

    EGLint num_configs;
    if (!handle.eglChooseConfig(g_EglDisplay, attribs, &bundle->config, 1, &num_configs)) {
        NSDebugLog(@"EGLBridge: Error couldn't get PBuffer config: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    assert(bundle->config);
    assert(num_configs > 0);

    if (useDesktopGL) {
        NSDebugLog(@"EGLBridge: Binding PBuffer to desktop OpenGL");
        if (!handle.eglBindAPI(EGL_OPENGL_API)) {
            NSDebugLog(@"EGLBridge: eglBindAPI(OPENGL_API) failed for PBuffer: 0x%x", handle.eglGetError());
        }
    } else {
        if (!handle.eglBindAPI(EGL_OPENGL_ES_API)) {
            NSDebugLog(@"EGLBridge: eglBindAPI failed for PBuffer: 0x%x", handle.eglGetError());
        }
    }

    const EGLint pbAttribs[] = {
        EGL_WIDTH, 16,
        EGL_HEIGHT, 16,
        EGL_NONE
    };
    bundle->surface = handle.eglCreatePbufferSurface(g_EglDisplay, bundle->config, pbAttribs);
    if (!bundle->surface) {
        NSDebugLog(@"EGLBridge: Error creating PBuffer surface: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    const EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    bundle->context = handle.eglCreateContext(g_EglDisplay, bundle->config, EGL_NO_CONTEXT, ctx_attribs);
    if (!bundle->context) {
        NSDebugLog(@"EGLBridge: Error creating PBuffer context: 0x%x", handle.eglGetError());
        handle.eglDestroySurface(g_EglDisplay, bundle->surface);
        free(bundle);
        return NULL;
    }

    return bundle;
}

void gl_destroy_context_only(gl_render_window_t* bundle) {
    if (!bundle) return;
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (bundle->surface) {
        handle.eglDestroySurface(g_EglDisplay, bundle->surface);
    }
    if (bundle->context) {
        handle.eglDestroyContext(g_EglDisplay, bundle->context);
    }
    free(bundle);
}

void gl_swap_interval(int swapInterval) {
    handle.eglSwapInterval(g_EglDisplay, swapInterval);
}

void gl_terminate() {
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    handle.eglDestroySurface(g_EglDisplay, currentBundle->gl.surface);
    handle.eglDestroyContext(g_EglDisplay, currentBundle->gl.context);
    handle.eglTerminate(g_EglDisplay);
    handle.eglReleaseThread();
    free(currentBundle);
    currentBundle = nil;
}

void set_gl_bridge_tbl() {
    br_init = gl_init;
    br_init_context = (br_init_context_t) gl_init_context;
    br_init_pbuffer_context = gl_init_pbuffer_context;
    br_make_current = (br_make_current_t) gl_make_current;
    br_swap_buffers = gl_swap_buffers;
    br_swap_interval = gl_swap_interval;
    br_terminate = gl_terminate;
}
