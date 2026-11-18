#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void *load(const char *path) {
    void *image = dlopen(path, RTLD_LAZY | RTLD_GLOBAL);
    if (!image) { fprintf(stderr, "%s\n", dlerror()); exit(2); }
    return image;
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    void *client;
    if (getenv("ST_TEST_CLIENT_FIRST")) {
        client = load(argv[2]);
        load(argv[1]);
    } else {
        load(argv[1]);
        client = load(argv[2]);
    }
    void (*probe)(void) = dlsym(client, "STRunSwiftUIProbe");
    if (!probe) return 2;
    probe();
    return 0;
}
