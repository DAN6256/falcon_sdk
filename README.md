# Falcon Framework Tutorial

Falcon is a C17 HTTP framework that serves HTTP/1.1 and HTTP/2, with TLS, routing, middleware, JWT authentication, database connection pooling (SQLite, PostgreSQL, MySQL), and a Redis KV client — all in a single static library that links with just `-lfalcon -lssl -lcrypto`.

This tutorial goes from zero to a production-ready API. Every code block compiles and runs as-is. Copy it, build it, and hit it with `curl` — that's the fastest way to learn.

> **Who is this for?** Backend engineers who want performance close to the metal without the overhead of a scripting language runtime. If you've written C before, you can ship a Falcon API in an afternoon.

> **What you'll build:** A complete Todo REST API with JWT auth, SQLite persistence, logging, CORS, rate limiting, and async database queries. Section 17 has the full example.

---

## Table of Contents

1. [Installation](#1-installation)
2. [Hello World](#2-hello-world)
3. [Path Parameters and Query Strings](#3-path-parameters-and-query-strings)
4. [Request Body and JSON](#4-request-body-and-json)
5. [Response Helpers](#5-response-helpers)
6. [Router Groups](#6-router-groups)
7. [Middleware](#7-middleware)
8. [JWT Authentication](#8-jwt-authentication)
9. [Background Tasks](#9-background-tasks)
10. [SQLite Database](#10-sqlite-database)
11. [PostgreSQL Database](#11-postgresql-database)
12. [MySQL / MariaDB Database](#12-mysql--mariadb-database)
13. [Redis Key-Value Store](#13-redis-key-value-store)
14. [TLS / HTTPS](#14-tls--https)
15. [Database Migrations](#15-database-migrations)
16. [Platform Notes](#16-platform-notes)
17. [Full Example: Todo API with JWT](#17-full-example-todo-api-with-jwt)
18. [Cookies](#18-cookies)
19. [Form Data and File Uploads](#19-form-data-and-file-uploads)
20. [Request Validation Patterns](#20-request-validation-patterns)
21. [Custom Error Handling](#21-custom-error-handling)
22. [Static File Serving](#22-static-file-serving)
23. [Testing Your Falcon App](#23-testing-your-falcon-app)
24. [Project Structure](#24-project-structure)
25. [Deployment](#25-deployment)

---

## 1. Installation

Falcon is distributed as a precompiled static library. libuv, nghttp2, and cJSON are
already linked in — your app only needs OpenSSL at link time. Source code is not
distributed; install from the packages below.

### Ubuntu / Debian (apt)

Add the official Falcon apt repository, then install:

```bash
echo "deb [arch=$(dpkg --print-architecture) trusted=yes] https://DAN6256.github.io/falcon_sdk/apt ./" \
  | sudo tee /etc/apt/sources.list.d/falcon.list
sudo apt update
sudo apt install libfalcon-dev libssl-dev
```

Headers land in `/usr/include/falcon/`. Libraries land in `/usr/lib/<arch>-linux-gnu/`.
`pkg-config` and `find_package(falcon)` work immediately after install.

### macOS

```bash
curl -fsSL https://DAN6256.github.io/falcon_sdk/install.sh | sudo sh
```

This detects your platform, downloads the right tarball, verifies the checksum, and
installs to `/usr/local`. To install without sudo, use a local prefix:

```bash
FALCON_PREFIX=$HOME/.local sh <(curl -fsSL https://DAN6256.github.io/falcon_sdk/install.sh)
```

You still need OpenSSL at link time — install it from Homebrew if you don't have it:

```bash
brew install openssl@3
```

> **Homebrew formula** — a `brew install falcon` formula is coming soon. Until then,
> the install script above is the one-command path on macOS.

### Windows

Use WSL2 running Ubuntu 24.04, then follow the Ubuntu apt instructions above.

```powershell
wsl --install -d Ubuntu-24.04
```

**Native Windows (vcpkg) — *coming soon*.** The vcpkg port is in progress.
For now, WSL2 is the recommended Windows path.

### Linux / macOS — one-line install script

Works on Linux (x86\_64 and arm64) and macOS (Apple Silicon). Detects your platform,
downloads the right release, verifies the checksum, and installs to `/usr/local`.

```bash
curl -fsSL https://DAN6256.github.io/falcon_sdk/install.sh | sudo sh
```

Custom prefix (no sudo required if you own the directory):

```bash
FALCON_PREFIX=$HOME/.local sh <(curl -fsSL https://DAN6256.github.io/falcon_sdk/install.sh)
```

> **Linux users:** the apt method above is recommended — it gets you `sudo apt upgrade`
> for free. Use the install script if you prefer not to add a third-party apt source.

### Manual install from GitHub release

Download the `.tar.gz` for your platform from the
[Falcon releases page](https://github.com/DAN6256/falcon_sdk/releases), then:

```bash
# Linux x86_64 example — substitute your platform
tar -xzf falcon-v1.0.0-linux-x86_64.tar.gz

# Create destination directories
sudo mkdir -p /usr/local/include \
              /usr/local/lib/pkgconfig \
              /usr/local/lib/cmake/falcon

# Install headers, libraries, pkg-config, and CMake files
sudo cp -r include/*            /usr/local/include/
sudo cp    lib/*.a              /usr/local/lib/
sudo cp -r lib/pkgconfig/*      /usr/local/lib/pkgconfig/
sudo cp -r lib/cmake/falcon/*   /usr/local/lib/cmake/falcon/
sudo ldconfig
```

Or install to a local prefix (no sudo required):

```bash
PREFIX=$HOME/.local
mkdir -p "$PREFIX/include" \
         "$PREFIX/lib/pkgconfig" \
         "$PREFIX/lib/cmake/falcon"
cp -r include/*            "$PREFIX/include/"
cp    lib/*.a              "$PREFIX/lib/"
cp -r lib/pkgconfig/*      "$PREFIX/lib/pkgconfig/"
cp -r lib/cmake/falcon/*   "$PREFIX/lib/cmake/falcon/"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
```

### What's included

Each release ships three libraries:

| Library | Header | Purpose |
|---|---|---|
| `libfalcon.a` | `<falcon/falcon.h>` | HTTP server, routing, JWT, middleware |
| `libfalcon_db.a` | `<falcon/falcon_db.h>` | SQLite, PostgreSQL, MySQL |
| `libfalcon_kv.a` | `<falcon/falcon_kv.h>` | Redis |

`libfalcon_db` and `libfalcon_kv` depend on system client libraries at your app's link
time (see Section 16 for platform-specific details). The core `libfalcon` depends only
on OpenSSL.

### Verify the install

```bash
pkg-config --modversion falcon
# 1.0.0

pkg-config --libs falcon
# -lfalcon -lssl -lcrypto
```

---

## 2. Hello World

Falcon is single-process and event-driven. `falcon_app_new()` creates the app state.
`falcon_run` starts the event loop — it blocks until the process receives `SIGINT` or
`SIGTERM`, then shuts down cleanly. Routes are registered before `falcon_run` is called.

```c
#include <falcon/falcon.h>

static void hello(falcon_ctx *ctx) {
    falcon_text(ctx, 200, "Hello, World!\n");
}

int main(void) {
    falcon_app *app = falcon_app_new();
    falcon_get(app, "/", hello);
    falcon_run(app, NULL);
    falcon_app_free(app);
    return 0;
}
```

### Compile and run

**With pkg-config (recommended for small projects):**
```bash
gcc -o hello hello.c $(pkg-config --cflags --libs falcon)
./hello
# Listening on http://0.0.0.0:8080

curl http://localhost:8080/
# Hello, World!
```

**With CMake (recommended for anything larger than a single file):**

`CMakeLists.txt`:
```cmake
cmake_minimum_required(VERSION 3.20)
project(hello C)
find_package(falcon REQUIRED)
add_executable(hello hello.c)
target_link_libraries(hello PRIVATE falcon::falcon)
```

```bash
cmake -S . -B build && cmake --build build
./build/hello
```

**Linking manually (if pkg-config is unavailable):**
```bash
gcc -o hello hello.c \
    -I/usr/local/include \
    -L/usr/local/lib -lfalcon -lssl -lcrypto
./hello
```

### Configuring host and port

Pass `falcon_serve_opts` as the second argument to `falcon_run`. Passing `NULL` uses
defaults (`0.0.0.0:8080`).

```c
int main(void) {
    falcon_app *app = falcon_app_new();
    falcon_get(app, "/", hello);

    falcon_serve_opts opts = {
        .host = "127.0.0.1",  /* localhost only — don't expose to network */
        .port = "9000",
    };
    falcon_run(app, &opts);
    falcon_app_free(app);
    return 0;
}
```

Override port at runtime with an environment variable (common in container environments):

```c
const char *port = getenv("PORT");
if (!port || !port[0]) port = "8080";

falcon_serve_opts opts = { .port = port };
falcon_run(app, &opts);
```

```bash
PORT=9000 ./hello
# Listening on http://0.0.0.0:9000
```

### HTTP/2

Falcon speaks HTTP/2 automatically when TLS is configured (see Section 14). Without TLS
it serves HTTP/1.1. No code change required to support HTTP/2 — just add the cert and key.

### Graceful shutdown

`falcon_run` catches `SIGINT` (Ctrl+C) and `SIGTERM` (the signal Docker/systemd sends
on stop). It waits for in-flight requests to finish before returning. After `falcon_run`
returns, call `falcon_app_free` and close any database pools.

```c
int rc = falcon_run(app, &opts);
/* only reaches here after shutdown signal */
falcon_app_free(app);
falcon_db_pool_close(db);  /* if using DB */
return rc ? 1 : 0;
```

---

## 3. Path Parameters and Query Strings

### Path parameters

Parameters start with `:` and match exactly one URL path segment. They are
URL-decoded automatically — a request to `/users/john%20doe` gives `"john doe"`.

```c
static void get_user(falcon_ctx *ctx) {
    const char *id = falcon_param(ctx, "id");
    /* id = "42" for GET /users/42 */
    falcon_text(ctx, 200, id);
}

falcon_get(app, "/users/:id", get_user);
```

`falcon_param` returns `NULL` if the name doesn't match any parameter in the
pattern — this can't happen if the route pattern and handler agree, but it's
good to know.

### Multiple parameters

```c
falcon_get(app, "/orgs/:org/repos/:repo", handler);
/* falcon_param(ctx, "org")  → "anthropic"  */
/* falcon_param(ctx, "repo") → "falcon"     */
```

There's no limit to the number of parameters in one pattern.

### Converting parameters to integers

Path parameters are always strings. Convert and validate before use:

```c
static void get_item(falcon_ctx *ctx) {
    const char *id_str = falcon_param(ctx, "id");
    char *endp;
    long id = strtol(id_str, &endp, 10);
    if (*endp != '\0' || id <= 0 || id > INT_MAX)
        FALCON_ABORT(ctx, 400, "id must be a positive integer");

    /* id is now a valid positive integer */
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"id\":%ld}", id);
    falcon_json_str(ctx, 200, buf);
}
```

Always validate. A user can send `/items/abc` or `/items/-1` — you get that
string, not a crash.

### Wildcard / catch-all routes

Use `/*` to match anything below a prefix (useful for 404 handlers or SPA
fallback):

```c
static void not_found(falcon_ctx *ctx) {
    char body[256];
    snprintf(body, sizeof(body),
             "{\"error\":\"no route for %s %s\"}",
             falcon_method(ctx), falcon_path(ctx));
    falcon_json_str(ctx, 404, body);
}

falcon_get(app,    "/*", not_found);
falcon_post(app,   "/*", not_found);
falcon_put(app,    "/*", not_found);
falcon_delete(app, "/*", not_found);
```

Register wildcard routes after all specific routes. Falcon matches routes in
registration order and stops at the first match.

### Query string

`falcon_query` returns the (URL-decoded) value for a named parameter, or `NULL`
if the key is absent.

```c
static void search(falcon_ctx *ctx) {
    const char *q    = falcon_query(ctx, "q");      /* "hello world" (decoded) */
    const char *page = falcon_query(ctx, "page");   /* "2" or NULL             */
    int page_num = page ? atoi(page) : 1;
    if (page_num < 1) page_num = 1;

    /* GET /search?q=hello+world&page=2 */
    falcon_text(ctx, 200, q ? q : "(empty)");
}
```

Both `+` (form-encoded space) and `%20` (percent-encoded space) are decoded to
a space character.

### Handling missing optional query parameters

`falcon_query` returning `NULL` is the correct signal for an absent key. Treat
it as a default:

```c
const char *sort  = falcon_query(ctx, "sort");   /* NULL → default "id" */
const char *order = falcon_query(ctx, "order");  /* NULL → default "asc" */
if (!sort)  sort  = "id";
if (!order) order = "asc";
if (strcmp(order, "asc") != 0 && strcmp(order, "desc") != 0)
    FALCON_ABORT(ctx, 400, "order must be asc or desc");
```

### Raw query string

When you need to parse the query yourself or log the raw value:

```c
const char *raw = falcon_query_str(ctx);
/* "q=hello+world&page=2" — NOT decoded, exactly as the client sent it */
```

---

## 4. Request Body and JSON

Falcon uses [cJSON](https://github.com/DaveGamble/cJSON) for JSON parsing — it's
statically linked in, no extra install needed. A few key rules: `falcon_body_json`
lazily parses and caches the body — the returned pointer is owned by `ctx`, do not
free it. `falcon_body_raw` gives you the bytes as received — NOT null-terminated, use
the returned length.

### JSON body

```c
static void create_item(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    if (!body) {
        /* Body was empty, not valid JSON, or Content-Type wasn't application/json */
        falcon_json_str(ctx, 400, "{\"error\":\"invalid JSON\"}");
        return;
    }

    cJSON *name = cJSON_GetObjectItem(body, "name");
    if (!cJSON_IsString(name) || !name->valuestring[0]) {
        falcon_json_str(ctx, 422, "{\"error\":\"name is required\"}");
        return;
    }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "created", name->valuestring);
    falcon_json(ctx, 201, resp);  /* falcon_json frees resp */
}
```

### Accessing nested objects and arrays

cJSON's object model maps directly to JSON — no magic. Navigate it explicitly:

```c
static void create_order(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    if (!body) FALCON_ABORT(ctx, 400, "invalid JSON");

    /* Nested object: { "address": { "city": "Accra" } } */
    cJSON *address = cJSON_GetObjectItem(body, "address");
    cJSON *city    = cJSON_GetObjectItem(address, "city");  /* NULL-safe if address is NULL */
    if (!cJSON_IsString(city))
        FALCON_ABORT(ctx, 422, "address.city required");

    /* Array: { "items": [{"sku":"A1","qty":2}, ...] } */
    cJSON *items = cJSON_GetObjectItem(body, "items");
    if (!cJSON_IsArray(items) || cJSON_GetArraySize(items) == 0)
        FALCON_ABORT(ctx, 422, "items array required");

    cJSON *item;
    cJSON_ArrayForEach(item, items) {
        cJSON *sku = cJSON_GetObjectItem(item, "sku");
        cJSON *qty = cJSON_GetObjectItem(item, "qty");
        if (!cJSON_IsString(sku) || !cJSON_IsNumber(qty))
            FALCON_ABORT(ctx, 422, "each item needs sku (string) and qty (number)");
    }

    falcon_json_str(ctx, 201, "{\"ok\":true}");
}
```

### Reading optional fields with defaults

```c
cJSON *body     = falcon_body_json(ctx);
cJSON *page_n   = cJSON_GetObjectItem(body, "page");
int    page     = cJSON_IsNumber(page_n) ? page_n->valueint : 1;
int    per_page = 20;

cJSON *per_n    = cJSON_GetObjectItem(body, "per_page");
if (cJSON_IsNumber(per_n) && per_n->valueint > 0 && per_n->valueint <= 100)
    per_page = per_n->valueint;
```

### Top-level JSON array

Some APIs POST a bare array rather than an object. Check with `cJSON_IsArray`:

```c
cJSON *body = falcon_body_json(ctx);
if (!cJSON_IsArray(body)) FALCON_ABORT(ctx, 400, "expected JSON array");

int n = cJSON_GetArraySize(body);
/* process each element with cJSON_GetArrayItem(body, i) */
```

### Raw body (for non-JSON content types)

```c
size_t      len;
const char *raw = falcon_body_raw(ctx, &len);
/* raw is NOT null-terminated; always use len for bounds checks */
if (!raw || len == 0) FALCON_ABORT(ctx, 400, "empty body");
```

Use `falcon_body_raw` for: URL-encoded forms, file uploads, XML, protobuf, or any
binary format.

### Checking the Content-Type

Falcon does not enforce Content-Type for you. Check it yourself when it matters:

```c
static void create_user(falcon_ctx *ctx) {
    const char *ct = falcon_header_in(ctx, "Content-Type");
    if (!ct || strncmp(ct, "application/json", 16) != 0)
        FALCON_ABORT(ctx, 415, "Content-Type must be application/json");

    cJSON *body = falcon_body_json(ctx);
    /* ... */
}
```

### Request metadata

```c
const char *method  = falcon_method(ctx);               /* "GET", "POST", "DELETE", ... */
const char *path    = falcon_path(ctx);                 /* URL-decoded path              */
const char *ct      = falcon_header_in(ctx, "Content-Type");
const char *auth    = falcon_header_in(ctx, "Authorization");
const char *ua      = falcon_header_in(ctx, "User-Agent");
```

`falcon_header_in` returns `NULL` if the header is absent. Header names are
case-insensitive.

---

## 5. Response Helpers

Every response function writes the status, headers, and body and marks the context as
responded. Calling a send function twice on the same `ctx` is a bug — the second call
is silently ignored. Set all headers before calling a send function.

### HTTP status codes

All send functions accept either a raw integer (`200`, `404`) or a named constant from
the `falcon_status` enum. The named constants give you IDE autocomplete and make
intent clearer at a glance:

```c
falcon_text(ctx, FALCON_OK,          "ok");
falcon_json(ctx, FALCON_CREATED,     obj);
falcon_send(ctx, FALCON_NO_CONTENT,  NULL, NULL, 0);
FALCON_ABORT(ctx, FALCON_NOT_FOUND,  "item not found");
FALCON_ABORT(ctx, FALCON_BAD_REQUEST,"missing field");
```

The full enum is in `<falcon/falcon.h>`. Common values:

| Constant | Code | Use when |
|---|---|---|
| `FALCON_OK` | 200 | Successful GET, PUT, PATCH |
| `FALCON_CREATED` | 201 | Successful POST that created a resource |
| `FALCON_NO_CONTENT` | 204 | Successful DELETE with no response body |
| `FALCON_BAD_REQUEST` | 400 | Malformed JSON, missing required header |
| `FALCON_UNAUTHORIZED` | 401 | Missing or invalid authentication |
| `FALCON_FORBIDDEN` | 403 | Authenticated but not allowed |
| `FALCON_NOT_FOUND` | 404 | Resource doesn't exist |
| `FALCON_CONFLICT` | 409 | Duplicate key, state conflict |
| `FALCON_UNSUPPORTED_MEDIA` | 415 | Wrong Content-Type |
| `FALCON_UNPROCESSABLE` | 422 | Valid JSON but failed validation |
| `FALCON_TOO_MANY_REQUESTS` | 429 | Rate limit exceeded |
| `FALCON_INTERNAL_ERROR` | 500 | Unexpected server error |
| `FALCON_SERVICE_UNAVAILABLE` | 503 | DB pool exhausted, dependency down |

### Text (Content-Type: text/plain)

```c
falcon_text(ctx, FALCON_OK, "plain text response");
```

### JSON from a cJSON object

`falcon_json` serializes the cJSON tree, sends the response, and **frees the object**.
You do not call `cJSON_Delete` after this.

```c
cJSON *obj = cJSON_CreateObject();
cJSON_AddNumberToObject(obj, "count", 42);
cJSON_AddBoolToObject(obj,   "ok",    1);
falcon_json(ctx, 200, obj);
/* obj is now freed — don't use it */
```

### JSON from a string literal

Use when you have a pre-built JSON string. Slightly faster than creating a cJSON tree.

```c
falcon_json_str(ctx, 200, "{\"status\":\"ok\"}");
```

For dynamic values, use `snprintf` into a stack buffer:

```c
char body[256];
snprintf(body, sizeof(body), "{\"id\":%ld,\"name\":\"%s\"}", id, name);
falcon_json_str(ctx, 201, body);
```

Note: this does not escape `name`. If `name` comes from user input, use cJSON:

```c
cJSON *obj = cJSON_CreateObject();
cJSON_AddNumberToObject(obj, "id",   id);
cJSON_AddStringToObject(obj, "name", name);  /* cJSON escapes special chars */
falcon_json(ctx, 201, obj);
```

### Custom content type

```c
/* HTML */
falcon_send(ctx, 200, "text/html; charset=utf-8", "<h1>Hello</h1>", 14);

/* Binary — e.g., an image already in memory */
falcon_send(ctx, 200, "image/png", png_bytes, png_len);

/* CSV download */
falcon_set_header(ctx, "Content-Disposition", "attachment; filename=\"report.csv\"");
falcon_send(ctx, 200, "text/csv", csv_buf, csv_len);
```

### Response headers

Set headers before calling any send function. You can call `falcon_set_header`
multiple times for different header names:

```c
falcon_set_header(ctx, "X-Request-Id",  "abc-123");
falcon_set_header(ctx, "Cache-Control", "no-store");
falcon_set_header(ctx, "X-RateLimit-Remaining", "99");
falcon_json_str(ctx, 200, "{\"ok\":true}");
```

The maximum number of response headers is `FALCON_MAX_RES_HEADERS` (16 by default).
Exceeding this is silently capped.

### Redirect

```c
/* Permanent redirect */
falcon_set_header(ctx, "Location", "/new-path");
falcon_text(ctx, 301, "");

/* Temporary redirect */
falcon_set_header(ctx, "Location", "/login");
falcon_text(ctx, 302, "");
```

### No-content responses (204)

```c
static void delete_item(falcon_ctx *ctx) {
    /* ... perform delete ... */
    falcon_send(ctx, FALCON_NO_CONTENT, NULL, NULL, 0);
}
```

### Abort early (stops middleware chain and any further handlers)

`FALCON_ABORT` sends `{"error":"..."}` as JSON and returns from the current function.
Use it for early exits in handlers and middleware:

```c
static void handler(falcon_ctx *ctx) {
    if (!user_exists(id))
        FALCON_ABORT(ctx, FALCON_NOT_FOUND, "user not found");

    /* This line only runs if user_exists returned true */
    falcon_json_str(ctx, FALCON_OK, "{}");
}
```

`FALCON_ABORT` sends `Content-Type: text/plain`. If you want JSON errors, use an
explicit check + `falcon_json_str` + `return` instead.

---

## 6. Router Groups

A router group prefixes a set of routes and can have its own middleware. Middleware
added with `falcon_router_use` runs only for routes in that group — not for other
groups or top-level routes.

```c
falcon_router_t *api = falcon_router(app, "/api/v1");

falcon_router_get(api,    "/health",    health_handler);
falcon_router_get(api,    "/users",     list_users);
falcon_router_post(api,   "/users",     create_user);
falcon_router_get(api,    "/users/:id", get_user);
falcon_router_put(api,    "/users/:id", update_user);
falcon_router_delete(api, "/users/:id", delete_user);
```

The full URLs registered above are: `GET /api/v1/health`, `GET /api/v1/users`, etc.

### Per-router middleware

```c
falcon_router_use(api, falcon_mw_jwt);
/* Now every route in `api` requires a valid JWT. Public routes on the
   top-level app are unaffected. */
```

### Multiple groups with different middleware

A common pattern: public routes at the top level, authenticated routes under `/api`,
and an admin group with stricter access:

```c
falcon_app *app = falcon_app_new();

/* Global middleware — runs for every request */
falcon_use(app, falcon_mw_logger);
falcon_use(app, falcon_mw_cors);

/* Public endpoints — no auth */
falcon_get(app,  "/health", health_handler);
falcon_post(app, "/auth/login", login_handler);

/* Authenticated API — JWT required */
falcon_router_t *api = falcon_router(app, "/api/v1");
falcon_router_use(api, falcon_mw_jwt);
falcon_router_get(api,  "/me",      profile_handler);
falcon_router_get(api,  "/items",   list_items);
falcon_router_post(api, "/items",   create_item);

/* Admin section — stricter rate limit + role check */
static void require_admin(falcon_ctx *ctx, falcon_next_fn next) {
    cJSON *claims = falcon_jwt_claims(ctx);
    cJSON *role   = cJSON_GetObjectItem(claims, "role");
    if (!cJSON_IsString(role) || strcmp(role->valuestring, "admin") != 0)
        FALCON_ABORT(ctx, 403, "admin only");
    next(ctx);
}

falcon_router_t *admin = falcon_router(app, "/admin");
falcon_router_use(admin, falcon_mw_jwt);
falcon_router_use(admin, require_admin);
falcon_router_get(admin,    "/users",      admin_list_users);
falcon_router_delete(admin, "/users/:id",  admin_delete_user);
```

### API versioning

Run two versions of your API simultaneously during a migration:

```c
falcon_router_t *v1 = falcon_router(app, "/api/v1");
falcon_router_t *v2 = falcon_router(app, "/api/v2");

falcon_router_get(v1, "/items", v1_list_items);
falcon_router_get(v2, "/items", v2_list_items);  /* new response shape */
```

---

## 7. Middleware

Middleware functions have the signature `void fn(falcon_ctx *ctx, falcon_next_fn next)`.
They run in registration order. Call `next(ctx)` to pass control to the next middleware
or to the route handler. Return without calling `next` to short-circuit the chain and
respond immediately.

### Execution order

```
Request arrives
    │
    ▼
[global mw 1]  ← falcon_use(app, ...)
    │
    ▼
[global mw 2]
    │
    ▼
[router mw]    ← falcon_router_use(router, ...)
    │
    ▼
[route handler]
    │
    ▼
Response sent
```

Global middleware registered with `falcon_use` runs for every request. Router
middleware registered with `falcon_router_use` runs only for routes in that router.

### Built-in middleware

```c
#include <falcon/falcon_middleware.h>

/* Logger: prints "[falcon] GET /items → 200 (12ms)" to stderr */
falcon_use(app, falcon_mw_logger);

/* CORS: allows all origins, standard methods, 24h max-age */
falcon_use(app, falcon_mw_cors);

/* Rate limiter: 100 req/min per IP, responds 429 when exceeded */
falcon_use(app, falcon_mw_rate_limit);
```

### Middleware with options

Wrap the `_with` variant in a static function to capture options. Using `static`
means the options struct is initialized once and never heap-allocated:

```c
static void my_cors(falcon_ctx *ctx, falcon_next_fn next) {
    static const falcon_mw_cors_opts opts = {
        .allow_origin  = "https://myapp.com",
        .allow_methods = "GET,POST,PUT,DELETE,OPTIONS",
        .allow_headers = "Authorization,Content-Type",
        .max_age       = 3600,
    };
    falcon_mw_cors_with(ctx, next, &opts);
}
falcon_use(app, my_cors);
```

Rate limiter keyed by a header (useful behind a load balancer where the real IP
is in `X-Forwarded-For`):

```c
static void api_rate_limit(falcon_ctx *ctx, falcon_next_fn next) {
    static const falcon_mw_rate_limit_opts opts = {
        .requests_per_minute = 60,
        .key_header = "X-Forwarded-For",  /* key by real IP, not proxy IP */
    };
    falcon_mw_rate_limit_with(ctx, next, &opts);
}
```

### Custom middleware

```c
static void require_api_key(falcon_ctx *ctx, falcon_next_fn next) {
    const char *key = falcon_header_in(ctx, "X-API-Key");
    if (!key || strcmp(key, "secret-key") != 0) {
        falcon_json_str(ctx, 401, "{\"error\":\"invalid API key\"}");
        return;  /* do NOT call next — chain stops here */
    }
    next(ctx);   /* key is valid — continue to handler */
}

falcon_use(app, require_api_key);
```

### Before and after a handler

Middleware can run code both before and after `next`:

```c
static void timing_mw(falcon_ctx *ctx, falcon_next_fn next) {
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    next(ctx);  /* run the rest of the chain */

    struct timespec t1;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long ms = (t1.tv_sec - t0.tv_sec) * 1000
            + (t1.tv_nsec - t0.tv_nsec) / 1000000;
    fprintf(stderr, "%s %s → %dms\n",
            falcon_method(ctx), falcon_path(ctx), (int)ms);
}
```

### Sharing state between middleware and handlers

Use a custom context pattern with `falcon_ctx_set_user_data`:

```c
typedef struct {
    int         user_id;
    const char *role;
} AuthInfo;

static void auth_mw(falcon_ctx *ctx, falcon_next_fn next) {
    cJSON *claims = falcon_jwt_claims(ctx);
    cJSON *sub    = cJSON_GetObjectItem(claims, "sub");
    cJSON *role   = cJSON_GetObjectItem(claims, "role");

    AuthInfo *info = malloc(sizeof(*info));
    info->user_id  = sub  ? atoi(sub->valuestring)  : 0;
    info->role     = role ? role->valuestring : "user";
    falcon_ctx_set_user_data(ctx, info, free);  /* free called on ctx destroy */

    next(ctx);
}

static void my_handler(falcon_ctx *ctx) {
    AuthInfo *info = falcon_ctx_get_user_data(ctx);
    /* info->user_id and info->role are available here */
    (void)info;
    falcon_json_str(ctx, 200, "{\"ok\":true}");
}
```

---

## 8. Model System — Struct ↔ JSON Mapping

`falcon_model.h` eliminates the `cJSON_CreateObject` / `cJSON_AddStringToObject`
boilerplate. Define your fields once; get the struct, JSON serializer,
deserializer, and validator for free.

```c
#include <falcon/falcon_model.h>
```

### Defining a model

```c
#define TODO_FIELDS(F)                  \
    F(INT,  id,    "id",    0)          \
    F(STR,  title, "title", 1, 256)     \
    F(BOOL, done,  "done",  0)

FALCON_MODEL(Todo, TODO_FIELDS)
```

This generates:

```c
typedef struct {
    int  id;
    char title[256];
    int  done;
    uint32_t _fields_set;   /* bitmask: bit N set = field N was present in JSON input */
} Todo;

cJSON *Todo_to_json  (const Todo *m);
int    Todo_from_json(const cJSON *j, Todo *out, char *errbuf, size_t errsz);
int    Todo_validate (const Todo *m, char *errbuf, size_t errsz);
```

### Field types

| Macro | C type | JSON type | Extra arg |
|---|---|---|---|
| `F(INT, name, "key", req)` | `int` | number | — |
| `F(INT64, name, "key", req)` | `long long` | number | — |
| `F(DOUBLE, name, "key", req)` | `double` | number | — |
| `F(BOOL, name, "key", req)` | `int` | boolean | — |
| `F(STR, name, "key", req, maxlen)` | `char[maxlen]` | string | max length |

`req=1` means required: `from_json` returns 0 with an error message if absent.
`req=0` means optional: absent fields leave the C field zero-initialized.

### Parsing a request body

```c
static void create_todo(falcon_ctx *ctx) {
    FALCON_PARSE_BODY(ctx, Todo, body);
    /* body.title is populated and validated — or 400 was already sent */

    Todo todo = { .id = next_id(), .done = 0 };
    strncpy(todo.title, body.title, sizeof(todo.title) - 1);
    FALCON_SEND_MODEL(ctx, 201, &todo, Todo);
}
```

`FALCON_PARSE_BODY(ctx, Type, varname)` expands to:
1. Parse `falcon_body_json(ctx)` into a `Type varname`
2. Validate required fields
3. On any error: send `400` with the error message and `return`

### Sending a response

```c
FALCON_SEND_MODEL(ctx, 200, &todo, Todo);
/* equivalent to: cJSON *j = Todo_to_json(&todo); falcon_json(ctx, 200, j); */
```

For arrays:

```c
FALCON_SEND_MODEL_ARRAY(ctx, 200, todos, count, Todo);
```

### Manual serialization

```c
cJSON *j = Todo_to_json(&todo);
cJSON_AddStringToObject(j, "extra_field", "value");  /* augment before sending */
falcon_json(ctx, 200, j);
```

### Tracking which fields were supplied (PATCH semantics)

`_fields_set` is a bitmask set by `from_json`. Bit N corresponds to field N in
definition order (0-indexed). Useful for PATCH endpoints where you only want to
update supplied fields:

```c
#define TODO_FIELDS(F) \
    F(STR,  title, "title", 0, 256)   /* bit 0 */ \
    F(BOOL, done,  "done",  0)        /* bit 1 */

FALCON_MODEL(TodoPatch, TODO_FIELDS)

static void patch_todo(falcon_ctx *ctx) {
    FALCON_PARSE_BODY(ctx, TodoPatch, patch);
    if (patch._fields_set & (1u << 0)) { /* title was supplied */ }
    if (patch._fields_set & (1u << 1)) { /* done was supplied  */ }
}
```

---

## 9. JWT Authentication

Include `<falcon/falcon_mw_jwt.h>` (links against OpenSSL, which is always present).

### HS256 (shared secret)

The simplest option: reads the secret from `FALCON_JWT_SECRET`.

```c
#include <falcon/falcon_mw_jwt.h>

// Reads FALCON_JWT_SECRET env var
falcon_use(app, falcon_mw_jwt);
```

Run with:
```bash
FALCON_JWT_SECRET="your-256-bit-secret" ./myapp
```

### HS256 with explicit secret

```c
static void jwt_auth(falcon_ctx *ctx, falcon_next_fn next) {
    static const falcon_mw_jwt_opts opts = {
        .secret = "my-secret-key",
    };
    falcon_mw_jwt_with(ctx, next, &opts);
}
falcon_use(app, jwt_auth);
```

### RS256 (RSA public key)

```c
static void jwt_rs256(falcon_ctx *ctx, falcon_next_fn next) {
    static const falcon_mw_jwt_opts opts = {
        .public_key_path = "/etc/myapp/jwt_public.pem",
    };
    falcon_mw_jwt_with(ctx, next, &opts);
}
falcon_router_use(api, jwt_rs256);
```

### Accessing claims in the handler

After successful JWT validation, access decoded claims via `falcon_jwt_claims`:

```c
static void profile(falcon_ctx *ctx) {
    cJSON *claims = falcon_jwt_claims(ctx);
    cJSON *sub    = cJSON_GetObjectItem(claims, "sub");

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "user_id", sub->valuestring);
    falcon_json(ctx, 200, resp);
}
```

### Issuer and audience validation

```c
static void jwt_strict(falcon_ctx *ctx, falcon_next_fn next) {
    static const falcon_mw_jwt_opts opts = {
        .secret   = "my-secret",
        .issuer   = "https://auth.myapp.com",
        .audience = "myapp-api",
    };
    falcon_mw_jwt_with(ctx, next, &opts);
}
```

### What the middleware validates

- Signature (HS256 or RS256)
- `exp` claim: token must not be expired
- `nbf` claim: token must be active (if present)
- `iss` claim: must match `opts.issuer` (if set)
- `aud` claim: must contain `opts.audience` (if set)

On failure: responds `401 Unauthorized` with `WWW-Authenticate: Bearer` and halts the chain. No need to check in the handler.

### Issuing tokens — login and signup

Include `<falcon/falcon_auth.h>` for password hashing and JWT signing. These
utilities are part of the `falcon` library — no extra dependencies.

```c
#include <falcon/falcon_auth.h>
```

**Key design rule:** signup creates the account and returns user data. Login
authenticates and returns the token. Conflating them confuses account creation
with session issuance — a user who signs up hasn't proven their password yet.

#### Users table schema

```sql
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT    NOT NULL UNIQUE,
    password_hash TEXT    NOT NULL   -- stored as "PBKDF2:<iter>:<salt_hex>:<hash_hex>"
);
```

#### Signup handler — returns user data, not a token

```c
typedef struct { char username[128]; } SignupCtx;

static void cb_signup(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) {
        /* UNIQUE constraint → duplicate username */
        falcon_json_str(ctx, 409, "{\"error\":\"username already taken\"}");
        return;
    }

    SignupCtx *sc = falcon_ctx_get_user_data(ctx);

    /* Get the auto-assigned id from the last insert */
    falcon_db_conn *conn2 = falcon_db_acquire(ctx);
    if (!conn2) {
        falcon_db_result_free(r);
        falcon_json_str(ctx, 503, "{\"error\":\"busy\"}");
        return;
    }
    falcon_db_result *id_r = falcon_db_query(conn2,
        "SELECT id FROM users WHERE username = ?",
        FALCON_DB_TEXT, sc->username, FALCON_DB_END);
    falcon_db_release(conn2);
    falcon_db_result_free(r);

    int uid = id_r ? atoi(falcon_db_result_get(id_r, 0, 0) ?: "0") : 0;
    falcon_db_result_free(id_r);

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddNumberToObject(resp, "id",       uid);
    cJSON_AddStringToObject(resp, "username", sc->username);
    falcon_json(ctx, 201, resp);
}

static void signup(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    if (!body) FALCON_ABORT(ctx, 400, "invalid JSON");

    cJSON *j_user = cJSON_GetObjectItem(body, "username");
    cJSON *j_pass = cJSON_GetObjectItem(body, "password");
    if (!cJSON_IsString(j_user) || !j_user->valuestring[0] ||
        !cJSON_IsString(j_pass) || !j_pass->valuestring[0])
        FALCON_ABORT(ctx, 400, "username and password required");

    /* Hash the password — returns "PBKDF2:<iter>:<salt_hex>:<hash_hex>" */
    char *hash = falcon_password_hash(j_pass->valuestring);
    if (!hash) FALCON_ABORT(ctx, 500, "server error");

    /* Store username for the callback (body JSON is request-scoped, not safe
     * to hold a pointer across an async boundary if body gets modified) */
    SignupCtx *sc = malloc(sizeof(*sc));
    strncpy(sc->username, j_user->valuestring, sizeof(sc->username) - 1);
    sc->username[sizeof(sc->username) - 1] = '\0';
    falcon_ctx_set_user_data(ctx, sc, free);

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) { free(hash); FALCON_ABORT(ctx, 503, "busy"); }

    int rc = falcon_db_async_query(ctx, conn, cb_signup,
        "INSERT INTO users (username, password_hash) VALUES (?, ?)",
        FALCON_DB_TEXT, j_user->valuestring,
        FALCON_DB_TEXT, hash,
        FALCON_DB_END);
    free(hash);
    if (rc != 0) { falcon_db_release(conn); FALCON_ABORT(ctx, 503, "busy"); }
}
```

> **User-data pattern:** to pass data into an async callback, store a
> heap-allocated struct before the async call with
> `falcon_ctx_set_user_data(ctx, ptr, free)` and retrieve it in the callback
> with `falcon_ctx_get_user_data(ctx)`.

#### Login handler — returns the token

```c
static void cb_login(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err || falcon_db_result_row_count(r) == 0) {
        falcon_db_result_free(r);
        falcon_json_str(ctx, 401, "{\"error\":\"invalid credentials\"}");
        return;
    }

    /* Copy out of the result before freeing it */
    char username[128], stored_hash[256];
    strncpy(username,    falcon_db_result_get(r, 0, 0) ?: "", sizeof(username) - 1);
    strncpy(stored_hash, falcon_db_result_get(r, 0, 1) ?: "", sizeof(stored_hash) - 1);
    falcon_db_result_free(r);

    const char *password = (const char *)falcon_ctx_get_user_data(ctx);
    if (!falcon_password_verify(password, stored_hash)) {
        falcon_json_str(ctx, 401, "{\"error\":\"invalid credentials\"}");
        return;
    }

    const char *secret = getenv("FALCON_JWT_SECRET");
    char *token = falcon_jwt_sign(username, secret, 3600);  /* 1-hour token */
    if (!token) { falcon_json_str(ctx, 500, "{\"error\":\"sign failed\"}"); return; }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "token", token);
    free(token);
    falcon_json(ctx, 200, resp);
}

static void login(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    if (!body) FALCON_ABORT(ctx, 400, "invalid JSON");

    cJSON *j_user = cJSON_GetObjectItem(body, "username");
    cJSON *j_pass = cJSON_GetObjectItem(body, "password");
    if (!cJSON_IsString(j_user) || !cJSON_IsString(j_pass))
        FALCON_ABORT(ctx, 400, "username and password required");

    /* Store password for the callback — body JSON is cached per-request but
     * strdup is safer for async code that may outlive the request object */
    falcon_ctx_set_user_data(ctx, strdup(j_pass->valuestring), free);

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "busy");

    falcon_db_async_query(ctx, conn, cb_login,
        "SELECT username, password_hash FROM users WHERE username = ?",
        FALCON_DB_TEXT, j_user->valuestring,
        FALCON_DB_END);
}
```

#### Wire up routes

```c
/* Public — no JWT required */
falcon_post(app, "/auth/signup", signup);
falcon_post(app, "/auth/login",  login);

/* Protected — JWT required */
falcon_router_t *api = falcon_router(app, "/api");
falcon_router_use(api, jwt_auth);
/* ... your protected routes ... */
```

#### Try it

```bash
# Sign up → receives user data (not a token)
curl -X POST http://localhost:8080/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"s3cur3"}'
# {"id":1,"username":"alice"}

# Log in → receives the token
curl -X POST http://localhost:8080/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"s3cur3"}'
# {"token":"eyJ..."}

# Use the token
curl -H "Authorization: Bearer eyJ..." http://localhost:8080/api/todos
```

### Async resolver middleware — resolving JWT to a user object

`falcon_mw_jwt` validates the token and stops there. Your handlers still need to
look up the user from the DB using `falcon_jwt_claims(ctx)`. With
`falcon_mw_auth_with`, the framework does that lookup for you: handlers call
`falcon_auth_user(ctx)` and receive the resolved user pointer directly.

```c
#include <falcon/falcon_auth.h>
#include <falcon/falcon_db.h>

typedef struct { int id; char username[128]; } User;

/* Step 1 — write the resolver: called after JWT validates, before the handler */
static void resolve_user(falcon_ctx *ctx, const char *sub,
                          void *arg, falcon_auth_done_fn done) {
    (void)arg;
    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) { done(ctx, NULL); return; }   /* NULL → 401 */

    /* sub is the JWT "sub" claim — we stored username there at login */
    typedef struct { falcon_db_conn *conn; falcon_auth_done_fn done; } RCtx;
    RCtx *rc = malloc(sizeof *rc);
    rc->conn = conn;
    rc->done = done;
    falcon_ctx_set_user_data(ctx, rc, free);

    if (falcon_db_async_query(ctx, conn, cb_resolve_user,
            "SELECT id, username FROM users WHERE username = ?",
            FALCON_DB_TEXT, sub, FALCON_DB_END) != 0) {
        falcon_db_release(conn);
        free(rc);
        done(ctx, NULL);
    }
}

static void cb_resolve_user(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    typedef struct { falcon_db_conn *conn; falcon_auth_done_fn done; } RCtx;
    RCtx *rc = falcon_ctx_get_user_data(ctx);

    if (err || !r || falcon_db_result_row_count(r) == 0) {
        falcon_db_result_free(r);
        rc->done(ctx, NULL);   /* user not found → 401 */
        return;
    }

    User *u = malloc(sizeof *u);
    u->id = atoi(falcon_db_result_get(r, 0, 0) ?: "0");
    strncpy(u->username, falcon_db_result_get(r, 0, 1) ?: "", sizeof(u->username) - 1);
    falcon_db_result_free(r);

    rc->done(ctx, u);   /* success: u is now accessible via falcon_auth_user(ctx) */
}

/* Step 2 — register the middleware */
static void auth_mw(falcon_ctx *ctx, falcon_next_fn next) {
    static falcon_mw_auth_opts opts = { .resolver = resolve_user };
    falcon_mw_auth_with(ctx, next, &opts);
}

/* Step 3 — use in protected handlers */
static void get_profile(falcon_ctx *ctx) {
    User *me = falcon_auth_user(ctx);  /* fully resolved — no JWT, no DB call */
    cJSON *resp = cJSON_CreateObject();
    cJSON_AddNumberToObject(resp, "id",       me->id);
    cJSON_AddStringToObject(resp, "username", me->username);
    free(me);   /* User was malloc'd by the resolver */
    falcon_json(ctx, 200, resp);
}

/* Step 4 — wire up */
falcon_router_t *api = falcon_router(app, "/api");
falcon_router_use(api, auth_mw);
falcon_router_get(api, "/profile", get_profile);
```

> **When to use `falcon_mw_auth_with` vs `falcon_mw_jwt`:**
> Use `falcon_mw_auth_with` when your handlers need a fully hydrated user object
> (roles, preferences, etc.) and you want to eliminate per-handler DB boilerplate.
> Use `falcon_mw_jwt` when you only need the raw claims and don't need a DB lookup
> for every request (e.g. a stateless microservice verifying tokens issued elsewhere).

### Generating a test token without a server

For quick curl tests before your login endpoint exists:

```bash
# Python (PyJWT)
python3 -c "import jwt,time; print(jwt.encode({'sub':'alice','exp':int(time.time())+3600},'your-secret'))"
```

### Common mistakes

**Mistake 1 — Hard-coded secret in production.** Always read the secret from an env var:

```c
/* Wrong */
static const falcon_mw_jwt_opts opts = { .secret = "my-secret" };

/* Right */
static void jwt_auth(falcon_ctx *ctx, falcon_next_fn next) {
    const char *secret = getenv("FALCON_JWT_SECRET");
    if (!secret || !secret[0]) {
        fprintf(stderr, "FATAL: FALCON_JWT_SECRET not set\n");
        exit(1);
    }
    falcon_mw_jwt_opts opts = { .secret = secret };
    falcon_mw_jwt_with(ctx, next, &opts);
}
```

**Mistake 2 — Forgetting `exp`.** A token without an `exp` claim never expires.
Always set an expiry in your token generation code.

**Mistake 3 — Using claims before checking them.** `falcon_jwt_claims` returns `NULL`
if no token was validated. Only call it inside a handler that's behind JWT middleware:

```c
static void profile(falcon_ctx *ctx) {
    cJSON *claims = falcon_jwt_claims(ctx);
    if (!claims) FALCON_ABORT(ctx, 401, "not authenticated");
    /* safe to use claims below */
}
```

---

## 10. Background Tasks

`falcon_after` schedules a callback to run after the HTTP response has been fully
sent to the client. The response is already gone — the client is not waiting —
so you can do slow work here without adding latency to the request.

Only one background task is allowed per request. You must register it before calling
any send function.

### Basic pattern

```c
static void log_event_fn(void *data) {
    const char *event = (const char *)data;
    /* write to a log file, call an analytics API, etc. */
    fprintf(stderr, "[analytics] %s\n", event);
    free(data);
}

static void purchase(falcon_ctx *ctx) {
    /* Process the purchase synchronously */
    falcon_json_str(ctx, 200, "{\"ok\":true}");

    /* Log asynchronously after the response is sent */
    falcon_after(ctx, log_event_fn, strdup("purchase_completed"));
}
```

The client gets the 200 response immediately. `log_event_fn` runs afterward in
the background.

### Sending a webhook after responding

```c
typedef struct {
    char url[256];
    char payload[512];
} WebhookTask;

static void send_webhook_fn(void *data) {
    WebhookTask *t = (WebhookTask *)data;
    /* Use libcurl or a simple socket to POST t->payload to t->url */
    fprintf(stderr, "[webhook] POST %s\n", t->url);
    free(t);
}

static void create_order(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    /* ... validate and save order ... */

    falcon_json_str(ctx, 201, "{\"order_id\":42}");

    WebhookTask *task = calloc(1, sizeof(*task));
    strncpy(task->url,     "https://example.com/hooks/order",  sizeof(task->url) - 1);
    strncpy(task->payload, "{\"event\":\"order.created\",\"id\":42}", sizeof(task->payload) - 1);
    falcon_after(ctx, send_webhook_fn, task);
}
```

### Cache invalidation

```c
typedef struct {
    falcon_kv_conn *conn;
    char key[128];
} EvictTask;

static void evict_fn(void *data) {
    EvictTask *t = (EvictTask *)data;
    /* Synchronous delete is fine here — we're already off the hot path */
    falcon_kv_del_sync(t->conn, t->key);
    falcon_kv_release(t->conn);
    free(t);
}

static void update_item(falcon_ctx *ctx) {
    /* ... update DB ... */
    falcon_json_str(ctx, 200, "{\"ok\":true}");

    EvictTask *task = calloc(1, sizeof(*task));
    task->conn = falcon_kv_acquire(ctx);
    snprintf(task->key, sizeof(task->key), "item:%s", falcon_param(ctx, "id"));
    falcon_after(ctx, evict_fn, task);
}
```

### What to avoid in background tasks

Background tasks run on the event loop after the response — do not do any I/O that
blocks the loop for more than a millisecond. For long operations (sending email,
calling a slow third-party API), write to a queue (Redis list, a local DB table)
and process it in a separate worker process.

---

## 11. SQLite Database

SQLite requires no server and stores everything in a single file. It's a great choice
for development, single-process apps, and read-heavy workloads. Because SQLite allows
only one writer at a time, keep the pool size to 1 for write-heavy apps.

```c
#include <falcon/falcon.h>
#include <falcon/falcon_db.h>
#include <falcon/falcon_sqlite.h>

/* File-based database */
falcon_db_pool_opts opts = { .pool_size = 1 };
falcon_db_pool *db = falcon_sqlite_open("./myapp.db", &opts);
if (!db) { fprintf(stderr, "Failed to open DB\n"); exit(1); }
falcon_app_set_db(app, db);
```

### In-memory database (useful for tests)

Use `:memory:` for a per-connection ephemeral database. Each connection in the pool
gets its own memory database, so use `pool_size = 1` to keep them synchronized:

```c
falcon_db_pool_opts opts = { .pool_size = 1 };
falcon_db_pool *db = falcon_sqlite_open(":memory:", &opts);
```

### Synchronous queries (boot time only)

Use `falcon_db_query` at startup (before accepting traffic) for schema creation and
migrations. These block the current thread, which is fine at boot:

```c
falcon_db_conn *conn = falcon_db_acquire(bctx);
falcon_db_result *r  = falcon_db_query(conn,
    "CREATE TABLE IF NOT EXISTS items ("
    "  id   INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  name TEXT NOT NULL,"
    "  done INTEGER NOT NULL DEFAULT 0"
    ")",
    FALCON_DB_END);
if (!r) fprintf(stderr, "Schema error\n");
falcon_db_result_free(r);
falcon_db_release(conn);
```

### Async queries (inside request handlers)

Inside a live request handler, **always use the async API**. Synchronous queries block
the event loop and kill throughput.

The pattern is always the same: acquire a connection, call `falcon_db_async_query`,
return. Your callback fires when the query completes.

```c
static void cb_items(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) {
        fprintf(stderr, "DB error: %s\n", err);
        falcon_json_str(ctx, 500, "{\"error\":\"database error\"}");
        return;
    }
    cJSON *arr = falcon_db_result_to_json(r);
    falcon_db_result_free(r);
    falcon_json(ctx, 200, arr);
}

static void list_items(falcon_ctx *ctx) {
    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "database busy");

    falcon_db_async_query(ctx, conn, cb_items,
        "SELECT id, name, done FROM items ORDER BY id",
        FALCON_DB_END);
    /* Return immediately. cb_items fires when the query finishes. */
}
```

### Parameterized queries

Always use parameterized queries. Never concatenate user input into SQL strings.

```c
/* String parameter */
falcon_db_async_query(ctx, conn, cb,
    "SELECT * FROM items WHERE name = ?",
    FALCON_DB_TEXT, search_term, FALCON_DB_END);

/* Multiple parameters */
falcon_db_async_query(ctx, conn, cb,
    "SELECT * FROM items WHERE user_id = ? AND done = ?",
    FALCON_DB_TEXT, user_id,
    FALCON_DB_TEXT, "0",
    FALCON_DB_END);

/* NULL value */
falcon_db_async_query(ctx, conn, cb,
    "INSERT INTO items (name, note) VALUES (?, ?)",
    FALCON_DB_TEXT, name,
    FALCON_DB_NULL,        /* note is NULL */
    FALCON_DB_END);
```

`FALCON_DB_END` is a sentinel that terminates the parameter list. You must always
include it. Forgetting it is undefined behavior.

### Reading results

```c
static void cb(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }

    int rows = falcon_db_result_row_count(r);
    int cols = falcon_db_result_col_count(r);

    for (int row = 0; row < rows; row++) {
        for (int col = 0; col < cols; col++) {
            const char *col_name = falcon_db_result_col_name(r, col);
            const char *val      = falcon_db_result_get(r, row, col);
            /* val is NULL for SQL NULL values — always check before using */
            if (val)
                printf("%s = %s\n", col_name, val);
        }
    }

    /* Or convert the entire result to a JSON array in one call */
    cJSON *arr = falcon_db_result_to_json(r);
    falcon_db_result_free(r);  /* always free the result */
    falcon_json(ctx, 200, arr);
}
```

### Transactions

Use `BEGIN` / `COMMIT` / `ROLLBACK` with the same connection. Chain them through
callbacks:

```c
static void cb_commit(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    falcon_db_result_free(r);
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"commit failed\"}"); return; }
    falcon_json_str(ctx, 201, "{\"ok\":true}");
}

static void cb_insert(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    falcon_db_conn *conn = (falcon_db_conn *)falcon_ctx_get_user_data(ctx);
    falcon_db_result_free(r);
    if (err) {
        falcon_db_async_query(ctx, conn, NULL, "ROLLBACK", FALCON_DB_END);
        falcon_json_str(ctx, 500, "{\"error\":\"insert failed\"}");
        return;
    }
    falcon_db_async_query(ctx, conn, cb_commit, "COMMIT", FALCON_DB_END);
}

static void cb_begin(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    falcon_db_conn *conn = (falcon_db_conn *)falcon_ctx_get_user_data(ctx);
    falcon_db_result_free(r);
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"begin failed\"}"); return; }

    const char *name = falcon_param(ctx, "name");
    falcon_db_async_query(ctx, conn, cb_insert,
        "INSERT INTO items (name) VALUES (?)",
        FALCON_DB_TEXT, name, FALCON_DB_END);
}

static void create_item_tx(falcon_ctx *ctx) {
    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "no connections");
    falcon_ctx_set_user_data(ctx, conn, NULL);  /* share conn across callbacks */
    falcon_db_async_query(ctx, conn, cb_begin, "BEGIN", FALCON_DB_END);
}
```

---

## 12. PostgreSQL Database

PostgreSQL is the right choice for production: concurrent writes, strong consistency,
JSONB, full-text search, and proper transactions. Falcon uses `libpq` under the hood.
The API is identical to SQLite — the only difference is how you open the pool, the
connection URL format, and a few SQL dialect differences.

```c
#include <falcon/falcon.h>
#include <falcon/falcon_db.h>
#include <falcon/falcon_pg.h>

const char *pg_url = getenv("DATABASE_URL");
/* Format: postgresql://user:password@host:port/dbname
   With SSL: postgresql://user:pass@host/db?sslmode=require
   Unix socket: postgresql:///mydb (connects via local socket) */

falcon_db_pool_opts opts = {
    .pool_size      = 10,    /* 10 concurrent connections — tune to your DB's max_connections */
    .max_result_rows = 10000, /* safety cap on result set size */
};
falcon_db_pool *db = falcon_pg_open(pg_url, &opts);
if (!db) { fprintf(stderr, "Failed to connect to PostgreSQL\n"); exit(1); }

falcon_app_set_db(app, db);
```

### Connection URL format

```
postgresql://[user[:password]@][host][:port][/dbname][?param=value&...]
```

Common parameters:
- `sslmode=require` — require SSL (recommended for production)
- `sslmode=disable` — no SSL (local development only)
- `connect_timeout=5` — fail fast if DB is unreachable
- `application_name=myapp` — shows in `pg_stat_activity`

```bash
DATABASE_URL="postgresql://appuser:s3cr3t@db.example.com:5432/myapp?sslmode=require&connect_timeout=5"
```

### RETURNING (PostgreSQL superpower)

PostgreSQL lets you `RETURNING` columns from an INSERT or UPDATE in the same query.
This avoids the two-query pattern required for MySQL:

```c
static void cb_created(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }
    cJSON *arr  = falcon_db_result_to_json(r);
    falcon_db_result_free(r);
    cJSON *item = cJSON_DetachItemFromArray(arr, 0);
    cJSON_Delete(arr);
    falcon_json(ctx, 201, item);
}

static void create_item(falcon_ctx *ctx) {
    cJSON *body  = falcon_body_json(ctx);
    cJSON *title = cJSON_GetObjectItem(body, "title");
    if (!cJSON_IsString(title)) FALCON_ABORT(ctx, 422, "title required");

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "db busy");

    /* INSERT + RETURNING in one round-trip */
    falcon_db_async_query(ctx, conn, cb_created,
        "INSERT INTO items (title) VALUES ($1) RETURNING id, title, created_at",
        FALCON_DB_TEXT, title->valuestring, FALCON_DB_END);
}
```

Note: PostgreSQL uses `$1`, `$2`, ... for parameters, not `?`. Falcon handles this
automatically — always use `FALCON_DB_TEXT` + positional varargs regardless of backend.

### UPDATE RETURNING (update + return the new row atomically)

```c
falcon_db_async_query(ctx, conn, cb,
    "UPDATE items SET done = true WHERE id = $1 AND user_id = $2 "
    "RETURNING id, title, done",
    FALCON_DB_TEXT, id_str,
    FALCON_DB_TEXT, user_id,
    FALCON_DB_END);
```

### Pool sizing guidelines

As a starting point: `pool_size = (number of CPU cores) * 2`. If your queries are
fast (< 5ms), fewer connections are fine. If queries are slow or you have burst
traffic, increase it. Your PostgreSQL server's `max_connections` is the hard ceiling —
leave headroom for migrations, `psql` sessions, and other clients.

### Cleanup

```c
int rc = falcon_run(app, &opts);
falcon_app_free(app);
falcon_db_pool_close(db);  /* waits for in-flight queries to finish */
return rc ? 1 : 0;
```

---

## 13. MySQL / MariaDB Database

Falcon's MySQL backend is fully compatible with both MySQL 5.7+, MySQL 8.0, and
MariaDB 10.4+. The API is identical to SQLite and PostgreSQL.

```c
#include <falcon/falcon.h>
#include <falcon/falcon_db.h>
#include <falcon/falcon_mysql.h>

const char *mysql_url = getenv("MYSQL_URL");
/* Format: mysql://user:password@host:port/dbname
   Example: mysql://appuser:s3cr3t@127.0.0.1:3306/myapp */

falcon_db_pool_opts opts = { .pool_size = 4, .max_result_rows = 5000 };
falcon_db_pool *db = falcon_mysql_open(mysql_url, &opts);
if (!db) { fprintf(stderr, "MySQL connect failed\n"); exit(1); }
falcon_app_set_db(app, db);
```

### INSERT and fetch the new row

MySQL has no `RETURNING` clause. Use `LAST_INSERT_ID()` in a follow-up query on the
same connection. Keep the same connection across both queries by stashing it in user data:

```c
static void cb_create_fetch(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }
    cJSON *arr  = falcon_db_result_to_json(r);
    falcon_db_result_free(r);
    cJSON *item = cJSON_DetachItemFromArray(arr, 0);
    cJSON_Delete(arr);
    falcon_json(ctx, 201, item);
}

static void cb_create(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }
    falcon_db_result_free(r);

    /* Reuse the same connection — LAST_INSERT_ID() is connection-scoped */
    falcon_db_conn *conn = (falcon_db_conn *)falcon_ctx_get_user_data(ctx);
    falcon_db_async_query(ctx, conn, cb_create_fetch,
        "SELECT id, title, done FROM items WHERE id = LAST_INSERT_ID()",
        FALCON_DB_END);
}

static void create_item(falcon_ctx *ctx) {
    cJSON *body  = falcon_body_json(ctx);
    cJSON *title = cJSON_GetObjectItem(body, "title");
    if (!cJSON_IsString(title)) FALCON_ABORT(ctx, 422, "title required");

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "no connections");
    falcon_ctx_set_user_data(ctx, conn, NULL);  /* share across callbacks */

    falcon_db_async_query(ctx, conn, cb_create,
        "INSERT INTO items (title) VALUES (?)",
        FALCON_DB_TEXT, title->valuestring, FALCON_DB_END);
}
```

### Boolean columns

MySQL stores booleans as `TINYINT(1)`. Pass `"1"` and `"0"` as text parameters:

```c
falcon_db_async_query(ctx, conn, cb,
    "UPDATE items SET done = ? WHERE id = ?",
    FALCON_DB_TEXT, is_done ? "1" : "0",
    FALCON_DB_TEXT, id_str,
    FALCON_DB_END);
```

When reading, `falcon_db_result_get` returns `"1"` or `"0"`. Compare with `strcmp`:

```c
const char *done_val = falcon_db_result_get(r, row, col);
int is_done = done_val && strcmp(done_val, "1") == 0;
```

### Transactions

MySQL supports transactions. Use `BEGIN` / `COMMIT` / `ROLLBACK` — these go through
`mysql_query()` automatically, not the prepared statement path:

```c
falcon_db_async_query(ctx, conn, cb_after_begin, "BEGIN", FALCON_DB_END);
/* then: INSERT / UPDATE / DELETE queries */
/* then: COMMIT or ROLLBACK */
```

### MariaDB compatibility

MariaDB 10.4+ supports `RETURNING` in `INSERT` statements:

```sql
INSERT INTO items (title) VALUES (?) RETURNING id, title
```

If you target MariaDB only, you can use this to avoid the two-step pattern. If you
target both MySQL and MariaDB, use `LAST_INSERT_ID()` for portability.

### Character set

Falcon connects with `utf8mb4` by default. If you see encoding issues, ensure your
table and column collations are also `utf8mb4`:

```sql
CREATE TABLE items (
    id    INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

---

## 14. Redis Key-Value Store

Redis is for fast, in-memory data: sessions, caches, rate limit counters, pub/sub,
and ephemeral state that doesn't need durability. Falcon uses `hiredis` under the hood.
The KV API is simpler than the DB API — values are always strings.

```c
#include <falcon/falcon_kv.h>
#include <falcon/falcon_redis.h>

const char *redis_url = getenv("REDIS_URL");
/* Formats:
   redis://localhost:6379               (no auth)
   redis://:password@host:6379          (password only)
   redis://user:password@host:6379/1    (user + password + db 1) */

falcon_kv_pool_opts kv_opts = { .pool_size = 4 };
falcon_kv_pool *kv = falcon_redis_open(redis_url, &kv_opts);
if (!kv) { fprintf(stderr, "Redis connect failed\n"); exit(1); }
falcon_app_set_kv(app, kv);
```

### GET

```c
static void cb_get(falcon_ctx *ctx, const char *val, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"kv\"}"); return; }
    if (!val) { falcon_json_str(ctx, 404, "{\"error\":\"not found\"}"); return; }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "value", val);
    falcon_json(ctx, 200, resp);
}

static void get_key(falcon_ctx *ctx) {
    const char *key  = falcon_param(ctx, "key");
    falcon_kv_conn *conn = falcon_kv_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "no kv connections");
    falcon_kv_async_get(ctx, conn, key, cb_get);
}
```

### SET with TTL

```c
static void cb_set(falcon_ctx *ctx, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"kv\"}"); return; }
    falcon_json_str(ctx, 200, "{\"ok\":true}");
}

static void set_key(falcon_ctx *ctx) {
    const char *key = falcon_param(ctx, "key");
    cJSON *body     = falcon_body_json(ctx);
    cJSON *val_node = cJSON_GetObjectItem(body, "value");
    if (!cJSON_IsString(val_node)) FALCON_ABORT(ctx, 400, "value required");

    falcon_kv_conn *conn = falcon_kv_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "no kv connections");

    falcon_kv_set_opts opts = { .ttl_seconds = 3600 };
    falcon_kv_async_set(ctx, conn, key, val_node->valuestring, &opts, cb_set);
}
```

### DEL

```c
static void cb_del(falcon_ctx *ctx, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"kv\"}"); return; }
    falcon_json_str(ctx, 200, "{\"deleted\":true}");
}

falcon_kv_async_del(ctx, conn, key, cb_del);
```

### Session storage pattern

Store JSON-encoded session data in Redis with a TTL. Use a random session ID as the key:

```c
#include <stdlib.h>

static void generate_session_id(char *out, size_t len) {
    const char chars[] = "abcdefghijklmnopqrstuvwxyz0123456789";
    for (size_t i = 0; i < len - 1; i++)
        out[i] = chars[rand() % (sizeof(chars) - 1)];
    out[len - 1] = '\0';
}

static void cb_session_saved(falcon_ctx *ctx, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"session\"}"); return; }
    /* session_id was set as a header before the async call */
    falcon_json_str(ctx, 200, "{\"ok\":true}");
}

static void login(falcon_ctx *ctx) {
    /* ... validate credentials ... */

    char session_id[33];
    generate_session_id(session_id, sizeof(session_id));

    /* Build session data */
    cJSON *session = cJSON_CreateObject();
    cJSON_AddStringToObject(session, "user_id", "42");
    cJSON_AddStringToObject(session, "role", "user");
    char *session_json = cJSON_PrintUnformatted(session);
    cJSON_Delete(session);

    char key[64];
    snprintf(key, sizeof(key), "sess:%s", session_id);

    /* Set cookie before the async call */
    char cookie[256];
    snprintf(cookie, sizeof(cookie),
             "session_id=%s; HttpOnly; Secure; SameSite=Strict; Max-Age=86400",
             session_id);
    falcon_set_header(ctx, "Set-Cookie", cookie);

    falcon_kv_conn *conn = falcon_kv_acquire(ctx);
    if (!conn) { free(session_json); FALCON_ABORT(ctx, 503, "kv busy"); }

    falcon_kv_set_opts opts = { .ttl_seconds = 86400 };
    falcon_kv_async_set(ctx, conn, key, session_json, &opts, cb_session_saved);
    free(session_json);
}
```

### Caching database results

```c
typedef struct { char key[128]; } CacheCtx;

static void cb_cache_miss(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }

    cJSON *arr = falcon_db_result_to_json(r);
    falcon_db_result_free(r);
    char *json = cJSON_PrintUnformatted(arr);

    /* Store in Redis for 5 minutes */
    CacheCtx *cc = (CacheCtx *)falcon_ctx_get_user_data(ctx);
    falcon_kv_conn *kconn = falcon_kv_acquire(ctx);
    if (kconn) {
        falcon_kv_set_opts opts = { .ttl_seconds = 300 };
        falcon_kv_async_set(ctx, kconn, cc->key, json, &opts, NULL);
    }

    falcon_json(ctx, 200, arr);
    free(json);
}

static void cb_cache_get(falcon_ctx *ctx, const char *val, const char *err) {
    if (!err && val) {
        /* Cache hit */
        falcon_json_str(ctx, 200, val);
        return;
    }
    /* Cache miss — query DB */
    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "db busy");
    falcon_db_async_query(ctx, conn, cb_cache_miss,
        "SELECT id, name FROM items ORDER BY id LIMIT 100",
        FALCON_DB_END);
}

static void list_items_cached(falcon_ctx *ctx) {
    CacheCtx *cc = calloc(1, sizeof(*cc));
    strncpy(cc->key, "items:list", sizeof(cc->key) - 1);
    falcon_ctx_set_user_data(ctx, cc, free);

    falcon_kv_conn *conn = falcon_kv_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "kv busy");
    falcon_kv_async_get(ctx, conn, cc->key, cb_cache_get);
}
```

---

## 15. TLS / HTTPS

Provide `tls_cert_path` and `tls_key_path` in `falcon_serve_opts`. When TLS is
configured, Falcon automatically negotiates HTTP/2 via ALPN (`h2`) with HTTP/1.1
as fallback. No code changes are needed — your handlers work the same over HTTP/1.1
and HTTP/2.

```c
falcon_serve_opts opts = {
    .host          = NULL,         /* 0.0.0.0 — all interfaces */
    .port          = "443",
    .tls_cert_path = "/etc/ssl/myapp.crt",
    .tls_key_path  = "/etc/ssl/myapp.key",
};
falcon_run(app, &opts);
```

### Self-signed cert for local development

```bash
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem \
  -days 365 -nodes -subj "/CN=localhost"
```

```bash
./myapp  # reads TLS_CERT and TLS_KEY env vars if no opts set
```

Or in code:

```c
falcon_serve_opts opts = {
    .port          = "8443",
    .tls_cert_path = "cert.pem",
    .tls_key_path  = "key.pem",
};
```

```bash
curl -k https://localhost:8443/health   # -k skips cert verification for self-signed
```

Browsers will show a security warning for self-signed certs — this is expected in
development. Use a real cert from Let's Encrypt for any shared environment.

### Let's Encrypt (production)

Use `certbot` to get free certs from Let's Encrypt. They auto-renew every 90 days.

```bash
# Install certbot (Ubuntu)
sudo apt install certbot

# Get a cert (standalone mode — temporarily binds port 80)
sudo certbot certonly --standalone -d api.example.com

# Certs land at:
# /etc/letsencrypt/live/api.example.com/fullchain.pem  ← use this for tls_cert_path
# /etc/letsencrypt/live/api.example.com/privkey.pem    ← use this for tls_key_path
```

```c
falcon_serve_opts opts = {
    .port          = "443",
    .tls_cert_path = "/etc/letsencrypt/live/api.example.com/fullchain.pem",
    .tls_key_path  = "/etc/letsencrypt/live/api.example.com/privkey.pem",
};
```

For cert renewal without downtime, point `tls_cert_path` and `tls_key_path` at the
symlinks Let's Encrypt creates — they update on renewal. Restart the app after renewal
with a systemd timer or a `certbot` deploy hook:

```bash
# /etc/letsencrypt/renewal-hooks/deploy/myapp.sh
#!/bin/bash
systemctl restart myapp
```

### HTTP to HTTPS redirect

Run Falcon on port 443 for HTTPS, and a tiny redirector on port 80:

```c
static void redirect_to_https(falcon_ctx *ctx) {
    char loc[256];
    snprintf(loc, sizeof(loc), "https://%s%s",
             falcon_header_in(ctx, "Host") ?: "example.com",
             falcon_path(ctx));
    falcon_set_header(ctx, "Location", loc);
    falcon_text(ctx, 301, "");
}

/* In a separate app / separate process on port 80 */
falcon_get(app, "/*", redirect_to_https);
```

Or let nginx handle the redirect (see Section 25).

### Reading TLS config from environment

```c
const char *cert = getenv("TLS_CERT");
const char *key  = getenv("TLS_KEY");
const char *port = getenv("PORT");

falcon_serve_opts opts = {
    .port          = port ?: "8080",
    .tls_cert_path = cert,   /* NULL → plain HTTP */
    .tls_key_path  = key,
};
falcon_run(app, &opts);
```

With `tls_cert_path = NULL`, Falcon serves plain HTTP. Set `TLS_CERT` and `TLS_KEY` in
production to enable HTTPS, leave them unset in local development.

### HTTP/2 behavior

HTTP/2 is only available over TLS (via ALPN negotiation). When a client that supports
HTTP/2 connects, Falcon uses multiplexed streams automatically. From your handler's
perspective nothing changes — `falcon_ctx` still represents a single request.

Clients that only support HTTP/1.1 continue to work — Falcon falls back automatically.

---

## 16. Database Migrations

Falcon's migration runner scans a directory for `.sql` files, applies them in
alphabetical order, and records each in a `_falcon_migrations` table so files are
applied at most once — even if you restart the app multiple times.

### Why migrations matter

Without a migration system, schema changes require manual `ALTER TABLE` commands on
every environment. With migrations, you commit a SQL file, and the next deploy applies
it automatically.

### Directory layout

Name files with a numeric prefix so they sort deterministically:

```
migrations/
  001_create_users.sql
  002_create_items.sql
  003_add_sessions.sql
  004_add_indexes.sql
  005_alter_users_add_phone.sql
```

Alphabetical order is the execution order. Zero-padding the numbers ensures correct
ordering past 9 (`010` sorts after `009`, not after `001`).

### Running migrations at boot

Always run migrations before `falcon_run`. If a migration fails, the app should
exit rather than start with a broken schema:

```c
falcon_db_conn *bc = falcon_db_acquire(bctx);
if (!bc) { fprintf(stderr, "Cannot acquire boot DB connection\n"); exit(1); }

int applied = falcon_db_migrate(bc, "./migrations");
if (applied < 0) {
    fprintf(stderr, "Migration failed — exiting\n");
    exit(1);
}
fprintf(stderr, "Applied %d migration(s)\n", applied);
falcon_db_release(bc);
```

### What `_falcon_migrations` contains

After the first run, your database gains:

```sql
CREATE TABLE _falcon_migrations (
    filename TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

Each applied file's basename is stored here. If you rename a migration file, the
runner will apply it again — don't rename files that have already been applied in
production.

### Writing migration files

**Prefer idempotent DDL where the database supports it:**

```sql
-- 001_create_users.sql
CREATE TABLE IF NOT EXISTS users (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    name  TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

**Multiple statements in one file are fine** — separate them with semicolons:

```sql
-- 003_add_sessions.sql
CREATE TABLE IF NOT EXISTS sessions (
    token   TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    expires TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
```

**`ALTER TABLE` is not idempotent** — wrap it if you need to re-run on multiple envs:

```sql
-- 005_alter_users_add_phone.sql
-- SQLite: ALTER TABLE ADD COLUMN is safe to run even if column exists on SQLite 3.37+
ALTER TABLE users ADD COLUMN phone TEXT;
```

For PostgreSQL:
```sql
-- 005_alter_users_add_phone.sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
```

### Rollback strategy

Falcon's runner only goes forward. There's no built-in rollback. For planned rollbacks,
write a `down` migration manually:

```sql
-- 005_rollback_phone.sql  (apply this manually if you need to undo 005)
ALTER TABLE users DROP COLUMN phone;
```

In production, prefer additive changes (new columns, new tables) over destructive
ones (dropping columns, renaming). You can always remove a column in a later migration
after the app no longer references it.

### Testing migrations

Run migrations against an in-memory SQLite database in your test suite to verify they
parse and execute without errors:

```c
static void test_migrations(void **state) {
    (void)state;
    falcon_db_pool_opts opts = { .pool_size = 1 };
    falcon_db_pool *db = falcon_sqlite_open(":memory:", &opts);
    assert_non_null(db);

    falcon_app *app = falcon_app_new();
    falcon_app_set_db(app, db);
    falcon_ctx *ctx = falcon_ctx_alloc(app);
    falcon_db_conn *conn = falcon_db_acquire(ctx);
    assert_non_null(conn);

    int applied = falcon_db_migrate(conn, "./migrations");
    assert_true(applied >= 0);

    /* Run again — should apply 0 files (idempotent) */
    int rerun = falcon_db_migrate(conn, "./migrations");
    assert_int_equal(rerun, 0);

    falcon_db_release(conn);
    falcon_ctx_free(ctx);
    falcon_app_free(app);
    falcon_db_pool_close(db);
}
```

---

## 17. Platform Notes

### macOS

Install with the one-line script:

```bash
curl -fsSL https://DAN6256.github.io/falcon_sdk/install.sh | sudo sh
```

You still need OpenSSL from Homebrew at link time:

```bash
brew install openssl@3
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig:$PKG_CONFIG_PATH"
```

If CMake can't locate OpenSSL, add this to your `CMakeLists.txt`:

```cmake
set(OPENSSL_ROOT_DIR "$ENV{HOMEBREW_PREFIX}/opt/openssl@3")
find_package(OpenSSL REQUIRED)
```

To use `falcon_db` or `falcon_kv` in your app, you also need the client libraries at link time (the backends are compiled into Falcon but the client libs must be present):

```bash
brew install sqlite postgresql mysql-client hiredis
```

### Linux (Ubuntu / Debian)

Install from the official Falcon apt repository (see [Section 1](#1-installation)):

```bash
echo "deb [arch=$(dpkg --print-architecture) trusted=yes] https://DAN6256.github.io/falcon_sdk/apt ./" \
  | sudo tee /etc/apt/sources.list.d/falcon.list
sudo apt update
sudo apt install libfalcon-dev libssl-dev
```

Headers land in `/usr/include/falcon/`. Libraries land in `/usr/lib/<arch>-linux-gnu/`.
`pkg-config` and `find_package` work automatically.

`libfalcon-dev` bundles all three libraries with all backends compiled in. To use `falcon_db`
or `falcon_kv` in your app, install the client libraries at link time:

```bash
# If your app uses falcon_db
sudo apt install libsqlite3-dev libpq-dev default-libmysqlclient-dev

# If your app uses falcon_kv
sudo apt install libhiredis-dev
```

Then link with:
```bash
gcc myapp.c $(pkg-config --cflags --libs falcon falcon_db falcon_kv)
```

Or in CMake:
```cmake
find_package(falcon REQUIRED)
find_package(falcon_db REQUIRED)
find_package(falcon_kv REQUIRED)
target_link_libraries(myapp PRIVATE falcon::falcon falcon::falcon_db falcon::falcon_kv)
```

### Windows

**WSL2 (recommended for most developers):**

The simplest path. Install WSL2 with Ubuntu 24.04, then follow the Linux apt instructions above.
All backends work. Your app runs as a native Linux binary inside WSL.

```powershell
wsl --install -d Ubuntu-24.04
```

Then inside WSL, follow the Linux apt instructions above.

**Native Windows (vcpkg + MSVC) — *coming soon*.**

The vcpkg port is in progress. Until then, WSL2 is the recommended Windows path.
Once available, the install will be:

```powershell
# coming soon
vcpkg install falcon openssl:x64-windows-static
```

### Docker

```dockerfile
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    echo "deb [arch=$(dpkg --print-architecture) trusted=yes] https://DAN6256.github.io/falcon_sdk/apt ./" \
      > /etc/apt/sources.list.d/falcon.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build \
    libfalcon-dev libssl-dev \
    libsqlite3-dev libpq-dev default-libmysqlclient-dev libhiredis-dev

COPY . /src
WORKDIR /src
RUN cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel

FROM ubuntu:24.04 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 libsqlite3-0 libpq5 libmysqlclient21 libhiredis0.14 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build/myapp /usr/local/bin/myapp
COPY migrations/ /app/migrations/
WORKDIR /app
ENV PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s CMD curl -f http://localhost:8080/health || exit 1
CMD ["myapp"]
```

The builder stage has all headers and static libs. The runtime stage only needs the
shared libraries your app dynamically links against (OpenSSL, SQLite, libpq, etc.).
The Falcon libraries themselves are statically linked into your binary — no `libfalcon`
package needed at runtime.

---

## 18. Full Example: Todo API with JWT

A complete, self-contained REST API: signup, login, JWT auth, and todo CRUD — all in one file.
Copy it to `todo_api.c`, compile, and run. No other files needed.

```c
/*
 * todo_api.c — complete Falcon example
 *
 * Compile:
 *   sudo apt install libsqlite3-dev libpq-dev default-libmysqlclient-dev
 *   gcc -o todo_api todo_api.c $(pkg-config --cflags --libs --static falcon falcon_db)
 *
 * Run:
 *   FALCON_JWT_SECRET=mysecret ./todo_api
 */

/* ── includes ────────────────────────────────────────────────────────── */
#include <falcon/falcon.h>
#include <falcon/falcon_db.h>
#include <falcon/falcon_sqlite.h>
#include <falcon/falcon_mw_jwt.h>
#include <falcon/falcon_auth.h>
#include <falcon/falcon_middleware.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── schema ──────────────────────────────────────────────────────────── */
static const char *SCHEMA_USERS =
    "CREATE TABLE IF NOT EXISTS users ("
    "  id            INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  username      TEXT    NOT NULL UNIQUE,"
    "  password_hash TEXT    NOT NULL"
    ")";

static const char *SCHEMA_TODOS =
    "CREATE TABLE IF NOT EXISTS todos ("
    "  id      INTEGER PRIMARY KEY AUTOINCREMENT,"
    "  user_id TEXT    NOT NULL,"
    "  title   TEXT    NOT NULL,"
    "  done    INTEGER NOT NULL DEFAULT 0,"
    "  created TEXT    NOT NULL DEFAULT (datetime('now'))"
    ")";

/* falcon_auth.h provides falcon_password_hash, falcon_password_verify,
 * and falcon_jwt_sign — no boilerplate needed here. */

static const char *jwt_secret(void) {
    const char *s = getenv("FALCON_JWT_SECRET");
    return (s && s[0]) ? s : "change-me-in-prod";
}

/* ── health ──────────────────────────────────────────────────────────── */
static void health(falcon_ctx *ctx) {
    falcon_json_str(ctx, 200, "{\"status\":\"ok\"}");
}

/* ── JWT middleware ───────────────────────────────────────────────────── */
static void jwt_auth(falcon_ctx *ctx, falcon_next_fn next) {
    falcon_mw_jwt_opts opts = { .secret = jwt_secret() };
    falcon_mw_jwt_with(ctx, next, &opts);
}

/* ── auth: signup ────────────────────────────────────────────────────── */
typedef struct { char username[128]; } SignupData;

static void cb_signup(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) {
        falcon_json_str(ctx, 409, "{\"error\":\"username taken\"}");
        return;
    }
    falcon_db_result_free(r);

    SignupData *d = falcon_ctx_get_user_data(ctx);

    /* Fetch the newly created id — conn2 is synchronous (boot-time only,
     * but signup is low-frequency so one sync query is fine here) */
    falcon_db_conn *conn2 = falcon_db_acquire(ctx);
    int uid = 0;
    if (conn2) {
        falcon_db_result *ir = falcon_db_query(conn2,
            "SELECT id FROM users WHERE username = ?",
            FALCON_DB_TEXT, d->username, FALCON_DB_END);
        falcon_db_release(conn2);
        if (ir) { uid = atoi(falcon_db_result_get(ir, 0, 0) ?: "0"); }
        falcon_db_result_free(ir);
    }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddNumberToObject(resp, "id",       uid);
    cJSON_AddStringToObject(resp, "username", d->username);
    falcon_json(ctx, 201, resp);
}

static void signup(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    if (!body) FALCON_ABORT(ctx, 400, "invalid JSON");

    cJSON *j_user = cJSON_GetObjectItem(body, "username");
    cJSON *j_pass = cJSON_GetObjectItem(body, "password");
    if (!cJSON_IsString(j_user) || !j_user->valuestring[0] ||
        !cJSON_IsString(j_pass) || !j_pass->valuestring[0])
        FALCON_ABORT(ctx, 400, "username and password required");

    char *hash = falcon_password_hash(j_pass->valuestring);
    if (!hash) FALCON_ABORT(ctx, 500, "server error");

    SignupData *d = malloc(sizeof(*d));
    strncpy(d->username, j_user->valuestring, sizeof(d->username) - 1);
    d->username[sizeof(d->username) - 1] = '\0';
    falcon_ctx_set_user_data(ctx, d, free);

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) { free(hash); FALCON_ABORT(ctx, 503, "busy"); }

    int rc = falcon_db_async_query(ctx, conn, cb_signup,
        "INSERT INTO users (username, password_hash) VALUES (?, ?)",
        FALCON_DB_TEXT, j_user->valuestring,
        FALCON_DB_TEXT, hash,
        FALCON_DB_END);
    free(hash);
    if (rc != 0) { falcon_db_release(conn); FALCON_ABORT(ctx, 503, "busy"); }
}

/* ── auth: login ─────────────────────────────────────────────────────── */
static void cb_login(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err || falcon_db_result_row_count(r) == 0) {
        falcon_db_result_free(r);
        falcon_json_str(ctx, 401, "{\"error\":\"invalid credentials\"}");
        return;
    }

    char username[128], stored_hash[256];
    strncpy(username,    falcon_db_result_get(r, 0, 0) ?: "", sizeof(username) - 1);
    strncpy(stored_hash, falcon_db_result_get(r, 0, 1) ?: "", sizeof(stored_hash) - 1);
    falcon_db_result_free(r);

    const char *password = (const char *)falcon_ctx_get_user_data(ctx);
    if (!falcon_password_verify(password, stored_hash)) {
        falcon_json_str(ctx, 401, "{\"error\":\"invalid credentials\"}");
        return;
    }

    char *token = falcon_jwt_sign(username, jwt_secret(), 3600);
    if (!token) { falcon_json_str(ctx, 500, "{\"error\":\"sign failed\"}"); return; }

    cJSON *resp = cJSON_CreateObject();
    cJSON_AddStringToObject(resp, "token", token);
    free(token);
    falcon_json(ctx, 200, resp);
}

static void login(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    if (!body) FALCON_ABORT(ctx, 400, "invalid JSON");

    cJSON *j_user = cJSON_GetObjectItem(body, "username");
    cJSON *j_pass = cJSON_GetObjectItem(body, "password");
    if (!cJSON_IsString(j_user) || !cJSON_IsString(j_pass))
        FALCON_ABORT(ctx, 400, "username and password required");

    falcon_ctx_set_user_data(ctx, strdup(j_pass->valuestring), free);

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "busy");

    falcon_db_async_query(ctx, conn, cb_login,
        "SELECT username, password_hash FROM users WHERE username = ?",
        FALCON_DB_TEXT, j_user->valuestring,
        FALCON_DB_END);
}

/* ── todo callbacks ──────────────────────────────────────────────────── */
static void cb_list(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }
    cJSON *arr = falcon_db_result_to_json(r);
    falcon_db_result_free(r);
    falcon_json(ctx, 200, arr);
}

static void cb_created(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }
    cJSON *arr  = falcon_db_result_to_json(r);
    falcon_db_result_free(r);
    cJSON *todo = cJSON_DetachItemFromArray(arr, 0);
    cJSON_Delete(arr);
    falcon_json(ctx, 201, todo);
}

static void cb_insert(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }
    falcon_db_result_free(r);
    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) { falcon_json_str(ctx, 503, "{\"error\":\"busy\"}"); return; }
    falcon_db_async_query(ctx, conn, cb_created,
        "SELECT id, user_id, title, done, created FROM todos"
        " WHERE rowid = last_insert_rowid()",
        FALCON_DB_END);
}

static void cb_done(falcon_ctx *ctx, falcon_db_result *r, const char *err) {
    if (err) { falcon_json_str(ctx, 500, "{\"error\":\"db\"}"); return; }
    int affected = falcon_db_result_row_count(r);
    falcon_db_result_free(r);
    if (!affected) { falcon_json_str(ctx, 404, "{\"error\":\"not found\"}"); return; }
    falcon_json_str(ctx, 200, "{\"ok\":true}");
}

/* ── todo handlers ───────────────────────────────────────────────────── */
static void list_todos(falcon_ctx *ctx) {
    cJSON *claims = falcon_jwt_claims(ctx);
    cJSON *sub    = cJSON_GetObjectItem(claims, "sub");
    const char *uid = sub ? sub->valuestring : "";

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "no connections");

    falcon_db_async_query(ctx, conn, cb_list,
        "SELECT id, title, done, created FROM todos WHERE user_id = ? ORDER BY id",
        FALCON_DB_TEXT, uid, FALCON_DB_END);
}

static void create_todo(falcon_ctx *ctx) {
    cJSON *claims = falcon_jwt_claims(ctx);
    cJSON *sub    = cJSON_GetObjectItem(claims, "sub");
    const char *uid = sub ? sub->valuestring : "";

    cJSON *body  = falcon_body_json(ctx);
    if (!body) FALCON_ABORT(ctx, 400, "invalid JSON");
    cJSON *title = cJSON_GetObjectItem(body, "title");
    if (!cJSON_IsString(title) || !title->valuestring[0])
        FALCON_ABORT(ctx, 400, "title required");

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "no connections");

    falcon_db_async_query(ctx, conn, cb_insert,
        "INSERT INTO todos (user_id, title) VALUES (?, ?)",
        FALCON_DB_TEXT, uid,
        FALCON_DB_TEXT, title->valuestring,
        FALCON_DB_END);
}

static void delete_todo(falcon_ctx *ctx) {
    cJSON *claims = falcon_jwt_claims(ctx);
    cJSON *sub    = cJSON_GetObjectItem(claims, "sub");
    const char *uid = sub ? sub->valuestring : "";
    const char *id  = falcon_param(ctx, "id");

    falcon_db_conn *conn = falcon_db_acquire(ctx);
    if (!conn) FALCON_ABORT(ctx, 503, "no connections");

    falcon_db_async_query(ctx, conn, cb_done,
        "DELETE FROM todos WHERE id = ? AND user_id = ?",
        FALCON_DB_TEXT, id,
        FALCON_DB_TEXT, uid,
        FALCON_DB_END);
}

/* ── main ────────────────────────────────────────────────────────────── */
int main(void) {
    falcon_db_pool *db = falcon_sqlite_open("./todos.db", NULL);
    if (!db) { fprintf(stderr, "Failed to open DB\n"); return 1; }

    /* Apply schema at boot */
    {
        falcon_app *tmp    = falcon_app_new();
        falcon_app_set_db(tmp, db);
        falcon_ctx *bctx   = falcon_ctx_alloc(tmp);
        falcon_db_conn *bc = falcon_db_acquire(bctx);
        if (bc) {
            falcon_db_result *r;
            r = falcon_db_query(bc, SCHEMA_USERS, FALCON_DB_END);
            falcon_db_result_free(r);
            r = falcon_db_query(bc, SCHEMA_TODOS, FALCON_DB_END);
            falcon_db_result_free(r);
            falcon_db_release(bc);
        }
        falcon_ctx_free(bctx);
        falcon_app_free(tmp);
    }

    falcon_app *app = falcon_app_new();
    falcon_app_set_db(app, db);

    falcon_use(app, falcon_mw_logger);
    falcon_use(app, falcon_mw_cors);

    /* Public — no auth */
    falcon_get(app,  "/health",      health);
    falcon_post(app, "/auth/signup", signup);
    falcon_post(app, "/auth/login",  login);

    /* Protected — JWT required */
    falcon_router_t *api = falcon_router(app, "/api");
    falcon_router_use(api, jwt_auth);
    falcon_router_get(api,    "/todos",     list_todos);
    falcon_router_post(api,   "/todos",     create_todo);
    falcon_router_delete(api, "/todos/:id", delete_todo);

    const char *port = getenv("PORT");
    if (!port || !port[0]) port = "8080";
    fprintf(stderr, "Listening on http://0.0.0.0:%s\n", port);

    falcon_serve_opts opts = { .port = port };
    int rc = falcon_run(app, &opts);
    falcon_app_free(app);
    falcon_db_pool_close(db);
    return rc ? 1 : 0;
}
```

### Compile and run

```bash
# Install system DB libs (needed because libfalcon_db.a bundles all backends)
sudo apt install libsqlite3-dev libpq-dev default-libmysqlclient-dev

# Compile
gcc -o todo_api todo_api.c $(pkg-config --cflags --libs --static falcon falcon_db)

# Run
FALCON_JWT_SECRET=mysecret ./todo_api
# Listening on http://0.0.0.0:8080
```

Manual flags (without pkg-config):
```bash
gcc -o todo_api todo_api.c \
    -I/usr/local/include -L/usr/local/lib \
    -lfalcon_db -lsqlite3 -lpq -lmysqlclient -lfalcon -lssl -lcrypto
```

### Try it

```bash
# 1 — sign up (returns user data, not a token)
curl -s -X POST http://localhost:8080/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"s3cur3"}'
# {"id":1,"username":"alice"}

# 2 — log in to get a token
TOKEN=$(curl -s -X POST http://localhost:8080/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"s3cur3"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# 3 — list todos (empty at first)
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/todos
# []

# 4 — create a todo
curl -s -X POST http://localhost:8080/api/todos \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Buy milk"}'
# {"id":1,"user_id":"alice","title":"Buy milk","done":0,"created":"..."}

# 5 — list again
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/todos

# 6 — delete
curl -s -X DELETE http://localhost:8080/api/todos/1 \
  -H "Authorization: Bearer $TOKEN"
# {"ok":true}

# 7 — wrong password → 401
curl -s -X POST http://localhost:8080/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"alice","password":"wrong"}'
# {"error":"invalid credentials"}

# 8 — no token → 401
curl -s http://localhost:8080/api/todos
```

---

## 19. Cookies

### Reading cookies

Cookies arrive in the `Cookie` request header as a single semicolon-separated string.
Falcon exposes the raw header; parse it yourself or with a small helper:

```c
static const char *get_cookie(falcon_ctx *ctx, const char *name) {
    const char *hdr = falcon_header_in(ctx, "Cookie");
    if (!hdr) return NULL;

    size_t nlen = strlen(name);
    const char *p = hdr;
    while (*p) {
        while (*p == ' ') p++;
        if (strncmp(p, name, nlen) == 0 && p[nlen] == '=')
            return p + nlen + 1;   /* points at value up to ';' or '\0' */
        p = strchr(p, ';');
        if (!p) break;
        p++;
    }
    return NULL;
}

static void handler(falcon_ctx *ctx) {
    const char *session = get_cookie(ctx, "session_id");
    if (!session) FALCON_ABORT(ctx, 401, "no session");
    falcon_text(ctx, 200, "welcome back");
}
```

The returned pointer is valid for the lifetime of the request context.

### Setting cookies

Set cookies via the `Set-Cookie` response header before calling a send function:

```c
static void login(falcon_ctx *ctx) {
    /* ... validate credentials ... */

    falcon_set_header(ctx, "Set-Cookie",
        "session_id=abc123; HttpOnly; Secure; SameSite=Strict; Max-Age=86400");
    falcon_json_str(ctx, 200, "{\"ok\":true}");
}
```

For multiple cookies, call `falcon_set_header` once per cookie (up to
`FALCON_MAX_RES_HEADERS`, currently 16).

### Deleting cookies

```c
falcon_set_header(ctx, "Set-Cookie",
    "session_id=; HttpOnly; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT");
falcon_json_str(ctx, 200, "{\"ok\":true}");
```

---

## 20. Form Data and File Uploads

### URL-encoded form data

HTML forms with `Content-Type: application/x-www-form-urlencoded` arrive as a
`key=value&key2=value2` body. Falcon doesn't auto-parse this, but the raw body
is one function call away:

```c
#include <string.h>
#include <stdlib.h>

/* Returns malloc'd value for `key` from URL-encoded `body`. Caller frees. */
static char *form_get(const char *body, size_t blen, const char *key) {
    size_t klen = strlen(key);
    const char *p = body;
    const char *end = body + blen;
    while (p < end) {
        const char *eq  = memchr(p, '=', (size_t)(end - p));
        if (!eq) break;
        const char *amp = memchr(eq + 1, '&', (size_t)(end - eq - 1));
        if (!amp) amp = end;

        if ((size_t)(eq - p) == klen && memcmp(p, key, klen) == 0) {
            size_t vlen = (size_t)(amp - eq - 1);
            char *val = malloc(vlen + 1);
            memcpy(val, eq + 1, vlen);
            val[vlen] = '\0';
            return val;
        }
        p = amp + 1;
    }
    return NULL;
}

static void submit_form(falcon_ctx *ctx) {
    size_t      blen;
    const char *body = falcon_body_raw(ctx, &blen);
    if (!body) FALCON_ABORT(ctx, 400, "empty body");

    char *username = form_get(body, blen, "username");
    char *password = form_get(body, blen, "password");

    if (!username || !password) {
        free(username); free(password);
        FALCON_ABORT(ctx, 400, "missing fields");
    }

    /* ... authenticate ... */

    free(username);
    free(password);
    falcon_json_str(ctx, 200, "{\"ok\":true}");
}
```

### File uploads (multipart/form-data)

Falcon exposes the raw body for multipart data. For simple single-file uploads,
read the body and write it to disk:

```c
#include <stdio.h>

static void upload(falcon_ctx *ctx) {
    size_t      len;
    const char *data = falcon_body_raw(ctx, &len);
    if (!data || len == 0) FALCON_ABORT(ctx, 400, "empty upload");

    /* For production: parse the Content-Type boundary and extract the file
     * part. Here we write the raw body for illustration. */
    FILE *fp = fopen("/tmp/upload.bin", "wb");
    if (!fp) FALCON_ABORT(ctx, 500, "could not open file");
    fwrite(data, 1, len, fp);
    fclose(fp);

    falcon_json_str(ctx, 201, "{\"saved\":true}");
}
```

For production multipart parsing, use a dedicated library such as
[multipart-parser-c](https://github.com/iafonov/multipart-parser-c) alongside
Falcon's `falcon_body_raw`.

---

## 21. Request Validation Patterns

Falcon has no automatic validation layer — that's a feature, not a gap. You
write explicit C validation, which is fast, readable, and produces exactly the
error messages you want.

### Extracting and checking required JSON fields

```c
typedef struct {
    const char *name;
    const char *email;
    int         age;
    int         age_valid;
} CreateUserReq;

static int parse_create_user(cJSON *body, CreateUserReq *out, char *errbuf, size_t errsz) {
    cJSON *name  = cJSON_GetObjectItem(body, "name");
    cJSON *email = cJSON_GetObjectItem(body, "email");
    cJSON *age   = cJSON_GetObjectItem(body, "age");

    if (!cJSON_IsString(name) || !name->valuestring[0]) {
        snprintf(errbuf, errsz, "name is required"); return 0;
    }
    if (!cJSON_IsString(email) || !strchr(email->valuestring, '@')) {
        snprintf(errbuf, errsz, "valid email required"); return 0;
    }
    if (cJSON_IsNumber(age)) {
        if (age->valueint < 0 || age->valueint > 150) {
            snprintf(errbuf, errsz, "age out of range"); return 0;
        }
        out->age       = age->valueint;
        out->age_valid = 1;
    }

    out->name  = name->valuestring;
    out->email = email->valuestring;
    return 1;
}

static void create_user(falcon_ctx *ctx) {
    cJSON *body = falcon_body_json(ctx);
    if (!body) FALCON_ABORT(ctx, 400, "invalid JSON");

    CreateUserReq req = {0};
    char errbuf[128];
    if (!parse_create_user(body, &req, errbuf, sizeof(errbuf))) {
        char resp[256];
        snprintf(resp, sizeof(resp), "{\"error\":\"%s\"}", errbuf);
        falcon_json_str(ctx, 422, resp);
        return;
    }

    /* req.name, req.email, req.age are safe to use */
    falcon_json_str(ctx, 201, "{\"ok\":true}");
}
```

### Validating path parameters

Path parameters are always strings. Convert and validate:

```c
static void get_item(falcon_ctx *ctx) {
    const char *id_str = falcon_param(ctx, "id");
    char *end;
    long id = strtol(id_str, &end, 10);
    if (*end != '\0' || id <= 0) FALCON_ABORT(ctx, 400, "invalid id");

    /* id is safe to use as a positive integer */
    (void)id;
    falcon_text(ctx, 200, "ok");
}
```

### Standardized error responses

Define a helper once and use it everywhere:

```c
static void send_error(falcon_ctx *ctx, int status, const char *code,
                        const char *detail) {
    char body[512];
    snprintf(body, sizeof(body),
             "{\"error\":{\"code\":\"%s\",\"detail\":\"%s\"}}",
             code, detail);
    falcon_json_str(ctx, status, body);
}

/* Usage */
send_error(ctx, 404, "NOT_FOUND", "item 42 does not exist");
send_error(ctx, 422, "VALIDATION", "email is required");
send_error(ctx, 409, "CONFLICT", "username already taken");
```

---

## 22. Custom Error Handling

### Not-found and method-not-allowed

Falcon returns plain-text 404/405 by default. Override with a catch-all route:

```c
static void not_found(falcon_ctx *ctx) {
    char body[128];
    snprintf(body, sizeof(body),
             "{\"error\":\"route %s %s not found\"}",
             falcon_method(ctx), falcon_path(ctx));
    falcon_json_str(ctx, 404, body);
}

falcon_get(app, "/*", not_found);
falcon_post(app, "/*", not_found);
/* ... register for every method you want to catch */
```

### Error middleware

A middleware that catches panics and turns them into clean JSON 500s:

```c
static void error_guard(falcon_ctx *ctx, falcon_next_fn next) {
    next(ctx);
    /* After next() returns: check if no response was sent */
    if (ctx->res_status == 0) {
        falcon_json_str(ctx, 500, "{\"error\":\"internal server error\"}");
    }
}

falcon_use(app, error_guard);
```

### Request ID for tracing

Assign a unique ID to every request — invaluable for correlating logs:

```c
#include <time.h>

static void request_id(falcon_ctx *ctx, falcon_next_fn next) {
    char id[32];
    snprintf(id, sizeof(id), "%lx-%lx",
             (unsigned long)time(NULL), (unsigned long)(uintptr_t)ctx);
    falcon_set_header(ctx, "X-Request-Id", id);
    next(ctx);
}

falcon_use(app, request_id);
```

---

## 23. Static File Serving

Falcon is an API framework. For static files in production, put nginx or a CDN
in front. For development, you can serve files directly:

```c
#include <stdio.h>
#include <sys/stat.h>
#include <stdlib.h>

static void serve_file(falcon_ctx *ctx, const char *path,
                        const char *content_type) {
    struct stat st;
    if (stat(path, &st) != 0) FALCON_ABORT(ctx, 404, "not found");

    FILE *fp = fopen(path, "rb");
    if (!fp)  FALCON_ABORT(ctx, 500, "could not open file");

    char *buf = malloc((size_t)st.st_size);
    if (!buf)  { fclose(fp); FALCON_ABORT(ctx, 500, "out of memory"); }
    fread(buf, 1, (size_t)st.st_size, fp);
    fclose(fp);

    falcon_send(ctx, 200, content_type, buf, (size_t)st.st_size);
    free(buf);
}

static void get_index(falcon_ctx *ctx) {
    serve_file(ctx, "./public/index.html", "text/html; charset=utf-8");
}

static void get_css(falcon_ctx *ctx) {
    const char *file = falcon_param(ctx, "file");
    char path[256];
    /* Prevent path traversal: reject any '/' or '..' in the param */
    if (strchr(file, '/') || strstr(file, ".."))
        FALCON_ABORT(ctx, 400, "invalid filename");
    snprintf(path, sizeof(path), "./public/css/%s", file);
    serve_file(ctx, path, "text/css; charset=utf-8");
}

falcon_get(app, "/",           get_index);
falcon_get(app, "/css/:file",  get_css);
```

For production: serve `/public/` from nginx and point your API prefix at Falcon.

---

## 24. Testing Your Falcon App

Falcon uses [CMocka](https://cmocka.org/) for unit tests. The pattern is always
the same: allocate an app + ctx, call the handler directly, assert on `ctx->res_status`
and the response body.

### CMakeLists.txt setup

```cmake
find_library(CMOCKA_LIB NAMES cmocka)
find_path(CMOCKA_INC NAMES cmocka.h)

add_executable(test_myapp tests/test_myapp.c)
target_include_directories(test_myapp PRIVATE ${CMOCKA_INC})
target_link_libraries(test_myapp PRIVATE falcon ${CMOCKA_LIB})
add_test(NAME test_myapp COMMAND test_myapp)
```

### Test file structure

```c
#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include <cmocka.h>

#include "falcon_internal.h"   /* for falcon_ctx_alloc, req_hdrs */
#include <falcon/falcon.h>

static int g_next_called;

static void dummy_next(falcon_ctx *ctx) {
    g_next_called++;
    falcon_json_str(ctx, 200, "{}");
}

/* ── test helpers ─────────────────────── */

static falcon_ctx *make_get(falcon_app *app, const char *path) {
    falcon_ctx *ctx = falcon_ctx_alloc(app);
    strncpy(ctx->method,   "GET",  sizeof(ctx->method)   - 1);
    strncpy(ctx->path_buf, path,   sizeof(ctx->path_buf) - 1);
    return ctx;
}

static falcon_ctx *make_post_json(falcon_app *app, const char *path,
                                   const char *body) {
    falcon_ctx *ctx = falcon_ctx_alloc(app);
    strncpy(ctx->method,   "POST", sizeof(ctx->method)   - 1);
    strncpy(ctx->path_buf, path,   sizeof(ctx->path_buf) - 1);
    if (body) {
        ctx->body     = (char *)body;
        ctx->body_len = strlen(body);
    }
    return ctx;
}

/* ── tests ───────────────────────────── */

static void test_health(void **state) {
    (void)state;
    falcon_app *app = falcon_app_new();
    falcon_ctx *ctx = make_get(app, "/health");

    /* Call the handler directly */
    extern void health_handler(falcon_ctx *);
    health_handler(ctx);

    assert_int_equal(ctx->res_status, 200);

    falcon_ctx_free(ctx);
    falcon_app_free(app);
}

static void test_create_item_missing_title(void **state) {
    (void)state;
    falcon_app *app = falcon_app_new();
    falcon_ctx *ctx = make_post_json(app, "/items", "{\"note\":\"hello\"}");

    extern void create_item(falcon_ctx *);
    create_item(ctx);

    assert_int_equal(ctx->res_status, 422);

    falcon_ctx_free(ctx);
    falcon_app_free(app);
}

/* ── runner ──────────────────────────── */

int main(void) {
    const struct CMUnitTest tests[] = {
        cmocka_unit_test(test_health),
        cmocka_unit_test(test_create_item_missing_title),
    };
    return cmocka_run_group_tests(tests, NULL, NULL);
}
```

### Testing middleware

```c
static void test_jwt_missing_header(void **state) {
    (void)state;
    falcon_app *app = falcon_app_new();
    falcon_ctx *ctx = make_get(app, "/protected");

    g_next_called = 0;
    falcon_mw_jwt_opts opts = { .secret = "secret" };
    falcon_mw_jwt_with(ctx, dummy_next, &opts);

    assert_int_equal(ctx->res_status, 401);
    assert_int_equal(g_next_called, 0);

    falcon_ctx_free(ctx);
    falcon_app_free(app);
}
```

### Running tests

```bash
# Build and run
cmake -B build -DFALCON_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build
ctest --test-dir build --output-on-failure

# Run a single test binary
./build/test_myapp
```

### Integration tests with a real database

```c
static falcon_db_pool *g_db;

static int setup(void **state) {
    (void)state;
    g_db = falcon_sqlite_open(":memory:", NULL);
    return g_db ? 0 : -1;
}

static int teardown(void **state) {
    (void)state;
    falcon_db_pool_close(g_db);
    return 0;
}

static void test_insert_and_fetch(void **state) {
    (void)state;
    falcon_app *app = falcon_app_new();
    falcon_app_set_db(app, g_db);
    falcon_ctx *ctx = falcon_ctx_alloc(app);

    /* Boot-time schema */
    falcon_db_conn *c = falcon_db_acquire(ctx);
    falcon_db_result *r = falcon_db_query(c,
        "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)",
        FALCON_DB_END);
    falcon_db_result_free(r);

    r = falcon_db_query(c,
        "INSERT INTO items (name) VALUES (?)",
        FALCON_DB_TEXT, "widget", FALCON_DB_END);
    falcon_db_result_free(r);

    r = falcon_db_query(c,
        "SELECT COUNT(*) FROM items", FALCON_DB_END);
    assert_string_equal(falcon_db_result_get(r, 0, 0), "1");
    falcon_db_result_free(r);
    falcon_db_release(c);

    falcon_ctx_free(ctx);
    falcon_app_free(app);
}

int main(void) {
    const struct CMUnitTest tests[] = {
        cmocka_unit_test_setup_teardown(test_insert_and_fetch, setup, teardown),
    };
    return cmocka_run_group_tests(tests, NULL, NULL);
}
```

---

## 25. Project Structure

For anything beyond a single-file demo, organize your Falcon app like this:

```
myapp/
├── CMakeLists.txt
├── src/
│   ├── main.c          ← app startup, falcon_run
│   ├── routes.c        ← route registration (falcon_get, falcon_post, ...)
│   ├── routes.h
│   ├── handlers/
│   │   ├── users.c     ← GET/POST /users handlers
│   │   ├── users.h
│   │   ├── items.c
│   │   └── items.h
│   ├── middleware/
│   │   ├── auth.c      ← JWT wrapper + custom middleware
│   │   └── auth.h
│   └── db/
│       ├── schema.c    ← run migrations at boot
│       └── schema.h
├── migrations/
│   ├── 001_create_users.sql
│   └── 002_add_items.sql
└── tests/
    ├── test_users.c
    └── test_items.c
```

### CMakeLists.txt for a multi-file app

```cmake
cmake_minimum_required(VERSION 3.20)
project(myapp C)

find_package(falcon REQUIRED)
find_package(falcon_db REQUIRED)   # if using DB

add_executable(myapp
    src/main.c
    src/routes.c
    src/handlers/users.c
    src/handlers/items.c
    src/middleware/auth.c
    src/db/schema.c
)

target_link_libraries(myapp PRIVATE falcon::falcon falcon::falcon_db)
```

### main.c

```c
#include <falcon/falcon.h>
#include <falcon/falcon_db.h>
#include <stdlib.h>
#include <stdio.h>

#include "routes.h"
#include "db/schema.h"

int main(void) {
    const char *db_url = getenv("DATABASE_URL");
    if (!db_url || !db_url[0]) db_url = "./myapp.db";

    falcon_db_pool *db = falcon_sqlite_open(db_url, NULL);
    if (!db) { fprintf(stderr, "DB open failed\n"); return 1; }

    /* Run migrations before accepting traffic */
    falcon_app *tmp  = falcon_app_new();
    falcon_app_set_db(tmp, db);
    schema_migrate(tmp);
    falcon_app_free(tmp);

    falcon_app *app = falcon_app_new();
    falcon_app_set_db(app, db);

    register_routes(app);

    const char *port = getenv("PORT");
    if (!port || !port[0]) port = "8080";
    fprintf(stderr, "Listening on :%s\n", port);

    falcon_serve_opts opts = { .port = port };
    falcon_run(app, &opts);
    falcon_app_free(app);
    falcon_db_pool_close(db);
    return 0;
}
```

### routes.c

```c
#include <falcon/falcon.h>
#include "routes.h"
#include "handlers/users.h"
#include "handlers/items.h"
#include "middleware/auth.h"

void register_routes(falcon_app *app) {
    falcon_use(app, falcon_mw_logger);
    falcon_use(app, falcon_mw_cors);

    falcon_get(app, "/health", health_handler);

    falcon_router_t *api = falcon_router(app, "/api/v1");
    falcon_router_use(api, jwt_auth);

    falcon_router_get(api,    "/users",      users_list);
    falcon_router_post(api,   "/users",      users_create);
    falcon_router_get(api,    "/users/:id",  users_get);
    falcon_router_delete(api, "/users/:id",  users_delete);

    falcon_router_get(api,    "/items",      items_list);
    falcon_router_post(api,   "/items",      items_create);
}
```

---

## 26. Deployment

### Docker

```dockerfile
FROM ubuntu:24.04 AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 libsqlite3-0 libpq5 libhiredis0.14 \
    && rm -rf /var/lib/apt/lists/*

COPY myapp /usr/local/bin/myapp
COPY migrations/ /app/migrations/

WORKDIR /app
ENV PORT=8080
EXPOSE 8080

CMD ["myapp"]
```

Build the binary on your host (or in a build stage), copy it in. The runtime image
only needs the shared libs — not build tools or headers.

#### Multi-stage build

```dockerfile
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build \
    libfalcon-dev libssl-dev libsqlite3-dev libpq-dev libhiredis-dev

COPY . /src
WORKDIR /src
RUN cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel

FROM ubuntu:24.04 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 libsqlite3-0 libpq5 libhiredis0.14 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build/myapp /usr/local/bin/myapp
COPY migrations/ /app/migrations/
WORKDIR /app
ENV PORT=8080
EXPOSE 8080
CMD ["myapp"]
```

### systemd service

`/etc/systemd/system/myapp.service`:

```ini
[Unit]
Description=My Falcon API
After=network.target postgresql.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/app
ExecStart=/usr/local/bin/myapp
Restart=on-failure
RestartSec=5

Environment=PORT=8080
Environment=DATABASE_URL=postgresql://user:pass@localhost/mydb
Environment=FALCON_JWT_SECRET=change-me-in-prod

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myapp
sudo journalctl -u myapp -f
```

### Reverse proxy with nginx

Falcon speaks HTTP/1.1 and HTTP/2. nginx in front handles SSL termination,
static files, and load balancing.

`/etc/nginx/sites-available/myapp`:

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate     /etc/ssl/api.example.com.crt;
    ssl_certificate_key /etc/ssl/api.example.com.key;

    # Static files served by nginx
    location /static/ {
        root /app/public;
    }

    # API proxied to Falcon
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### Health checks

Expose a `/health` endpoint for load balancers and container orchestrators:

```c
static void health(falcon_ctx *ctx) {
    falcon_json_str(ctx, 200, "{\"status\":\"ok\"}");
}

falcon_get(app, "/health", health);
```

Docker:
```dockerfile
HEALTHCHECK --interval=10s --timeout=3s \
  CMD curl -f http://localhost:8080/health || exit 1
```

Kubernetes:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

---

## What's Next

- **Multiple databases** — call `falcon_app_set_db` and `falcon_app_set_kv` together. Both pools are independent.
- **HTTP/2 push** — available via TLS (enabled automatically when `tls_cert_path` is set).
- **Custom response codes** — `falcon_send(ctx, 422, "application/json", body, len)`.
- **Graceful shutdown** — `falcon_run` blocks until the server stops. Send `SIGINT`/`SIGTERM` to exit.
- **Connection pooling** — `pool_size` in `falcon_db_pool_opts` / `falcon_kv_pool_opts` controls concurrency.
- **MongoDB** — `#include <falcon/falcon_mongo.h>` (implementation in v1.1).
