#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct Buffer {
  uint8_t *data;
  uintptr_t len;
} Buffer;

const char *openwater_init(void);

uint64_t add(uint64_t left, uint64_t right);

struct Buffer compile_typst(const char *typst_template_string);

void free_buf(struct Buffer buf);
