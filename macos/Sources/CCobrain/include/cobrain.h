// C ABI of crates/cobrain-ffi. Keep in sync with crates/cobrain-ffi/src/lib.rs.
#ifndef COBRAIN_H
#define COBRAIN_H

#include <stdint.h>
#include <stddef.h>

typedef struct CobrainDoc CobrainDoc;

char *cobrain_engine_version(void);
CobrainDoc *cobrain_new_blank(void);
CobrainDoc *cobrain_new_sample(void);
CobrainDoc *cobrain_open(const char *path);
int32_t cobrain_save(CobrainDoc *doc, const char *path);
void cobrain_free(CobrainDoc *doc);

uint32_t cobrain_page_count(CobrainDoc *doc);
int32_t cobrain_page_size(CobrainDoc *doc, uint32_t index, float *w, float *h);
uint8_t *cobrain_render_page(CobrainDoc *doc, uint32_t index, float scale, uint32_t *out_w, uint32_t *out_h);
void cobrain_free_buffer(uint8_t *ptr, size_t len);

int32_t cobrain_click(CobrainDoc *doc, uint32_t page, float x, float y);
int32_t cobrain_caret(CobrainDoc *doc, uint32_t *page, float *x, float *top, float *height);

char *cobrain_commands(CobrainDoc *doc);
char *cobrain_outline(CobrainDoc *doc);
char *cobrain_disabled_commands(CobrainDoc *doc);
char *cobrain_toggle_states(CobrainDoc *doc);
char *cobrain_contextual_tabs(CobrainDoc *doc);
char *cobrain_theme_colors(CobrainDoc *doc);
char *cobrain_gallery_styles(CobrainDoc *doc);
uint8_t *cobrain_style_preview(CobrainDoc *doc, const char *id, float w, float h, float scale, uint32_t *out_w, uint32_t *out_h);
char *cobrain_take_ui_requests(CobrainDoc *doc);
char *cobrain_para_state(CobrainDoc *doc);
char *cobrain_run(CobrainDoc *doc, const char *id, const char *params_json);
void cobrain_free_string(char *s);

#endif
