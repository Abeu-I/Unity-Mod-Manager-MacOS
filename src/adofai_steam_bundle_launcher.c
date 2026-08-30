#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int path_list_contains(const char *list, const char *value)
{
    const char *start;
    size_t value_length;

    if (list == NULL || value == NULL) {
        return 0;
    }

    value_length = strlen(value);
    start = list;
    while (*start != '\0') {
        const char *end = strchr(start, ':');
        size_t item_length = end == NULL ? strlen(start) : (size_t)(end - start);
        if (item_length == value_length && strncmp(start, value, value_length) == 0) {
            return 1;
        }
        if (end == NULL) {
            break;
        }
        start = end + 1;
    }
    return 0;
}

static int prepend_environment_once(const char *name, const char *value)
{
    const char *old_value = getenv(name);
    char *combined = NULL;
    int result;

    if (path_list_contains(old_value, value)) {
        return 0;
    }
    if (old_value != NULL && old_value[0] != '\0') {
        if (asprintf(&combined, "%s:%s", value, old_value) < 0) {
            return ENOMEM;
        }
        result = setenv(name, combined, 1);
        free(combined);
        return result == 0 ? 0 : errno;
    }
    return setenv(name, value, 1) == 0 ? 0 : errno;
}

static int parent_path(const char *input, char *output, size_t output_size)
{
    char scratch[PATH_MAX];
    char *parent;

    if (strlcpy(scratch, input, sizeof(scratch)) >= sizeof(scratch)) {
        return ENAMETOOLONG;
    }
    parent = dirname(scratch);
    if (strlcpy(output, parent, output_size) >= output_size) {
        return ENAMETOOLONG;
    }
    return 0;
}

int main(int argc, char **argv)
{
    char executable_path[PATH_MAX];
    char macos_dir[PATH_MAX];
    char contents_dir[PATH_MAX];
    char app_dir[PATH_MAX];
    char game_root[PATH_MAX];
    char real_game[PATH_MAX];
    char doorstop[PATH_MAX];
    char umm[PATH_MAX];
    char **child_argv;
    const char *executable_name;
    int index;

    if (realpath(argv[0], executable_path) == NULL) {
        perror("realpath launcher");
        return 71;
    }
    executable_name = strrchr(executable_path, '/');
    executable_name = executable_name == NULL ? executable_path : executable_name + 1;

    if (parent_path(executable_path, macos_dir, sizeof(macos_dir)) != 0 ||
        parent_path(macos_dir, contents_dir, sizeof(contents_dir)) != 0 ||
        parent_path(contents_dir, app_dir, sizeof(app_dir)) != 0 ||
        parent_path(app_dir, game_root, sizeof(game_root)) != 0) {
        fprintf(stderr, "ADOFAI launcher path is too long.\n");
        return 71;
    }

    if (snprintf(real_game, sizeof(real_game), "%s/%s.adofai-umm-x86_64",
                 macos_dir, executable_name) >= (int)sizeof(real_game) ||
        snprintf(doorstop, sizeof(doorstop), "%s/.adofai-umm-macos/libdoorstop.dylib",
                 game_root) >= (int)sizeof(doorstop) ||
        snprintf(umm, sizeof(umm),
                 "%s/Contents/Resources/Data/Managed/UnityModManager/UnityModManager.dll",
                 app_dir) >= (int)sizeof(umm)) {
        fprintf(stderr, "ADOFAI launcher component path is too long.\n");
        return 71;
    }

    if (access(real_game, X_OK) != 0 || access(doorstop, R_OK) != 0 || access(umm, R_OK) != 0) {
        fprintf(stderr, "ADOFAI mod-loader component is missing: %s\n", strerror(errno));
        return 71;
    }

    if (prepend_environment_once("DYLD_INSERT_LIBRARIES", doorstop) != 0 ||
        setenv("DOORSTOP_ENABLED", "1", 1) != 0 ||
        setenv("DOORSTOP_TARGET_ASSEMBLY", umm, 1) != 0 ||
        setenv("SteamAppId", "977950", 1) != 0 ||
        setenv("SteamGameId", "977950", 1) != 0) {
        perror("setenv");
        return 70;
    }
    unsetenv("DOORSTOP_ENABLE");
    unsetenv("DOORSTOP_INVOKE_DLL_PATH");

    child_argv = calloc((size_t)argc + 1, sizeof(char *));
    if (child_argv == NULL) {
        perror("calloc");
        return 70;
    }
    child_argv[0] = real_game;
    for (index = 1; index < argc; index++) {
        child_argv[index] = argv[index];
    }
    child_argv[argc] = NULL;

    execv(real_game, child_argv);
    fprintf(stderr, "Could not start ADOFAI: %s\n", strerror(errno));
    free(child_argv);
    return 71;
}
