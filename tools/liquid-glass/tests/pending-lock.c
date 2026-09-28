// Only the private nested compositor test may launch this deliberately slow
// lock client. It requests a lock without submitting a surface, reproducing
// the interval while a real locker prepares its first frame.
#include "session-lock-client.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

static struct ext_session_lock_manager_v1* manager;

static void global(void* data, struct wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
    (void)data;
    (void)version;
    if (!strcmp(interface, ext_session_lock_manager_v1_interface.name))
        manager = wl_registry_bind(registry, name, &ext_session_lock_manager_v1_interface, 1);
}

static void removed(void* data, struct wl_registry* registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

int main(void) {
    const char* expected = getenv("GLASS_LOCK_TEST_RUNTIME");
    const char* runtime = getenv("XDG_RUNTIME_DIR");
    const char* display = getenv("WAYLAND_DISPLAY");
    if (!expected || !runtime || strcmp(expected, runtime) || strncmp(runtime, "/tmp/gl-", 8)
        || !display || strchr(display, '/')) {
        fputs("Refusing to lock anything but the private glass test compositor\n", stderr);
        return 2;
    }
    struct wl_display* connection = wl_display_connect(NULL);
    if (!connection)
        return 3;
    struct wl_registry* registry = wl_display_get_registry(connection);
    const struct wl_registry_listener listener = {.global = global, .global_remove = removed};
    wl_registry_add_listener(registry, &listener, NULL);
    if (wl_display_roundtrip(connection) < 0 || !manager)
        return 4;
    ext_session_lock_manager_v1_lock(manager);
    if (wl_display_roundtrip(connection) < 0)
        return 5;
    puts("pending");
    fflush(stdout);
    while (wl_display_dispatch(connection) >= 0) {}
    wl_display_disconnect(connection);
    return 0;
}
