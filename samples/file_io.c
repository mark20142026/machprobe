#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>

int main(int argc, char **argv) {
    const char payload[] = "macOS ARM64 file round trip\n";
    char path[PATH_MAX], readback[sizeof payload] = {0};
    if (argc != 2) { fprintf(stderr, "usage: file_io DIRECTORY\n"); return 2; }
    int n = snprintf(path, sizeof path, "%s/machprobe-XXXXXX", argv[1]);
    if (n < 0 || (size_t)n >= sizeof path) { fputs("path too long\n", stderr); return 1; }
    int fd = mkstemp(path);
    if (fd < 0) { perror("mkstemp"); return 1; }
    FILE *stream = fdopen(fd, "w+");
    if (!stream) { perror("fdopen"); close(fd); unlink(path); return 1; }
    int ok = fwrite(payload, 1, sizeof payload - 1, stream) == sizeof payload - 1;
    ok = ok && fseek(stream, 0, SEEK_SET) == 0;
    ok = ok && fread(readback, 1, sizeof payload - 1, stream) == sizeof payload - 1;
    ok = ok && memcmp(payload, readback, sizeof payload - 1) == 0;
    if (fclose(stream) != 0) ok = 0;
    if (unlink(path) != 0) ok = 0;
    if (!ok) { fputs("file round trip failed\n", stderr); return 1; }
    puts("File I/O round trip OK");
    return 0;
}
