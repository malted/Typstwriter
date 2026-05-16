#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct Buffer {
  uint8_t *data;
  uintptr_t len;
} Buffer;

typedef struct CompileResult {
  struct Buffer pdf;
  char *error;
} CompileResult;

/**
 * Raster render result. `pixels` is premultiplied RGBA8, `width * height * 4`
 * bytes. `pages` is the total page count of the document (so the caller can
 * iterate). On error `pixels` is empty and `error` is non-null.
 */
typedef struct RenderResult {
  struct Buffer pixels;
  uint32_t width;
  uint32_t height;
  uint32_t pages;
  char *error;
} RenderResult;

/**
 * One page's pixels in a multi-page render.
 */
typedef struct PageRender {
  struct Buffer pixels;
  uint32_t width;
  uint32_t height;
} PageRender;

/**
 * Multi-page raster render result. `pages` points to `page_count` `PageRender`
 * entries. Free with `tw_free_render_all`.
 */
typedef struct RenderAllResult {
  struct PageRender *pages;
  uintptr_t page_count;
  char *error;
} RenderAllResult;

/**
 * One highlighted span. `start`/`len` are **byte offsets** into the UTF-8
 * source. `kind` is a `TwHighlightKind`.
 */
typedef struct HighlightRun {
  uint32_t start;
  uint32_t len;
  uint8_t kind;
  uint8_t _pad[3];
} HighlightRun;

typedef struct HighlightResult {
  struct HighlightRun *runs;
  uintptr_t count;
} HighlightResult;

/**
 * Optional explicit init — also called lazily on first source/compile.
 */
void tw_init(void);

/**
 * Insert or update the in-memory source for a file.
 */
void tw_set_source(const char *abs_path, const char *text);

/**
 * Compile `abs_main_path` to PDF. Returns a CompileResult; on failure `pdf`
 * is empty and `error` is a non-null C string (caller must free with
 * `tw_free_string`). On success `error` is null and caller frees `pdf` with
 * `tw_free_buf`.
 */
struct CompileResult tw_compile_pdf(const char *abs_main_path);

/**
 * Compile + raster-render a single page at `pixel_per_pt` (e.g. 2.0 for
 * retina-ish). Returns premultiplied RGBA8 ready to wrap in a CGImage with
 * `kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big`.
 */
struct RenderResult tw_render_page(const char *abs_main_path,
                                   uint32_t page_index,
                                   float pixel_per_pt);

/**
 * Compile + render every page individually. Returns a heap-allocated array of
 * `PageRender`; free with `tw_free_render_all`.
 */
struct RenderAllResult tw_render_all_pages(const char *abs_main_path, float pixel_per_pt);

/**
 * Compile + render the whole document as a single tall image (pages stacked
 * vertically with `gap_pt` points of whitespace between them). Background is
 * white.
 */
struct RenderResult tw_render_merged(const char *abs_main_path, float pixel_per_pt, float gap_pt);

void tw_free_render_all(struct RenderAllResult result);

void tw_free_buf(struct Buffer buf);

void tw_free_string(char *s);

/**
 * Parse `text` and return highlight runs. Spans may overlap (e.g. `Strong`
 * inside `Heading`); apply them outer-first so inner ranges win. Free with
 * `tw_free_highlight`.
 */
struct HighlightResult tw_highlight(const char *text);

void tw_free_highlight(struct HighlightResult result);

uint64_t add(uint64_t left, uint64_t right);
