// Wstrzykiwana przez DYLD_INSERT_LIBRARIES biblioteka wymuszająca pozycję
// startową okna SDL — pozycja wyznacza monitor, na którym gra robi fullscreen.
// Pozycja przychodzi w env QL_WINDOW_POS="x,y" (globalne współrzędne CG).
// Obsługuje SDL2 (QuakeSpasm) i SDL3 (vkQuake) — różne sygnatury SDL_CreateWindow.
#include <stdlib.h>
#include <stdio.h>
#include <dlfcn.h>
#include <stdbool.h>

typedef void SDL_Window;

#define INTERPOSE(_new, _orig)                                                  \
    __attribute__((used)) static struct { const void *n; const void *o; }       \
    _interpose_##_orig __attribute__((section("__DATA,__interpose"))) =         \
    { (const void *)&(_new), (const void *)&(_orig) }

static bool shim_pos(int *x, int *y) {
    const char *env = getenv("QL_WINDOW_POS");
    return env && sscanf(env, "%d,%d", x, y) == 2;
}

static bool is_sdl3(void) {
    // symbol istniejący wyłącznie w SDL3
    return dlsym(RTLD_DEFAULT, "SDL_CreateWindowWithProperties") != NULL;
}

typedef struct { int x, y, w, h; } shim_rect;

#define SHIM_WINDOWPOS_CENTERED_MASK 0x2FFF0000u

/// Monitor zawierający QL_WINDOW_POS: identyfikator (SDL3) albo indeks (SDL2).
/// Zwraca -1, gdy nie da się go wskazać.
static long shim_target_display(void) {
    int px, py;
    if (!shim_pos(&px, &py)) return -1;
    shim_rect r;
    if (is_sdl3()) {
        unsigned int *(*get_displays)(int *) = dlsym(RTLD_DEFAULT, "SDL_GetDisplays");
        bool (*get_bounds)(unsigned int, shim_rect *) = dlsym(RTLD_DEFAULT, "SDL_GetDisplayBounds");
        void (*sdl_free)(void *) = dlsym(RTLD_DEFAULT, "SDL_free");
        if (!get_displays || !get_bounds) return -1;
        int count = 0;
        unsigned int *ids = get_displays(&count);
        long found = -1;
        for (int i = 0; ids && i < count; i++) {
            if (get_bounds(ids[i], &r) && px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h) {
                found = (long)ids[i];
                break;
            }
        }
        if (ids && sdl_free) sdl_free(ids);
        return found;
    }
    // SDL2 operuje indeksami monitorów, nie identyfikatorami
    int (*get_count)(void) = dlsym(RTLD_DEFAULT, "SDL_GetNumVideoDisplays");
    int (*get_bounds2)(int, shim_rect *) = dlsym(RTLD_DEFAULT, "SDL_GetDisplayBounds");
    if (!get_count || !get_bounds2) return -1;
    for (int i = 0; i < get_count(); i++) {
        if (get_bounds2(i, &r) == 0 && px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h) {
            return i;
        }
    }
    return -1;
}

static unsigned int shim_centered_pos(void) {
    long display = shim_target_display();
    return display < 0 ? 0 : (SHIM_WINDOWPOS_CENTERED_MASK | (unsigned int)display);
}

// Deklaracja w kształcie SDL2; dla SDL3 czytamy tylko pierwsze 4 argumenty
// (title, w, h, flags trafiają do tych samych rejestrów).
extern SDL_Window *SDL_CreateWindow(const char *title, int a, int b, int c, int d, unsigned int e);

static SDL_Window *shim_CreateWindow(const char *title, int a, int b, int c, int d, unsigned int e) {
    int px, py;
    bool override = shim_pos(&px, &py);
    if (is_sdl3()) {
        // SDL3: SDL_CreateWindow(title, w, h, flags) — pozycję ustawia się po utworzeniu
        SDL_Window *(*create3)(const char *, int, int, unsigned long long) =
            (SDL_Window *(*)(const char *, int, int, unsigned long long))(void *)&SDL_CreateWindow;
        SDL_Window *win = create3(title, a, b, (unsigned long long)c);
        if (win && override) {
            bool (*setpos)(SDL_Window *, int, int) =
                (bool (*)(SDL_Window *, int, int))dlsym(RTLD_DEFAULT, "SDL_SetWindowPosition");
            if (setpos) setpos(win, px, py);
        }
        return win;
    }
    if (override) { a = px; b = py; }
    return SDL_CreateWindow(title, a, b, c, d, e);
}

INTERPOSE(shim_CreateWindow, SDL_CreateWindow);

// vkQuake (ścieżka SDL3) zaraz po utworzeniu okna wywołuje
//   SDL_SetWindowPosition(win, SDL_WINDOWPOS_CENTERED_DISPLAY(0), ...)
// bo przy porcie z SDL2 zostało tam 0 zamiast "brak monitora" (w SDL3 to nieprawidłowe
// ID i SDL centruje na głównym ekranie). To kasowało nasz wybór — przechwytujemy więc
// także zmiany pozycji i podstawiamy monitor wskazany w launcherze.
extern bool SDL_SetWindowPosition(SDL_Window *window, int x, int y);

static bool shim_SetWindowPosition(SDL_Window *window, int x, int y) {
    unsigned int centered = shim_centered_pos();
    if (centered) {
        x = y = (int)centered;
    } else {
        int px, py;
        if (shim_pos(&px, &py)) { x = px; y = py; }
    }
    return SDL_SetWindowPosition(window, x, y);
}

INTERPOSE(shim_SetWindowPosition, SDL_SetWindowPosition);

// Sama pozycja nie wystarcza: vkQuake tworzy okno większe niż ekran (np. 6400×4164),
// więc po wyśrodkowaniu zachodzi ono bardziej na monitor główny, a SDL wybiera ekran
// o największym pokryciu. Dlatego przy fullscreenie przypinamy monitor wprost —
// zamiast NULL (fullscreen "desktopowy") podajemy tryb pulpitu wybranego ekranu,
// przez co SDL_GetDisplayForWindow zwraca dokładnie ten monitor.
extern bool SDL_SetWindowFullscreenMode(SDL_Window *window, const void *mode);

static bool shim_SetWindowFullscreenMode(SDL_Window *window, const void *mode) {
    long display = shim_target_display();
    if (mode == NULL && display >= 0 && is_sdl3()) {
        const void *(*desktop_mode)(unsigned int) = dlsym(RTLD_DEFAULT, "SDL_GetDesktopDisplayMode");
        if (desktop_mode) {
            const void *m = desktop_mode((unsigned int)display);
            if (m) mode = m;
        }
    }
    return SDL_SetWindowFullscreenMode(window, mode);
}

INTERPOSE(shim_SetWindowFullscreenMode, SDL_SetWindowFullscreenMode);
