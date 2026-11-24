#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdbool.h>
#include <unistd.h>

#define N 8
#define CHUNK 25
#define CHUNKS 10

typedef void (*chunk_cb)(void**, size_t, void*);

static chunk_cb g_cb = NULL;
static void* g_user = NULL;
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static volatile int g_run = 0;

static void* run(void* p) {
  (void)p;
  uint64_t sn[CHUNK];
  double ch[N][CHUNK];
  uint8_t ct[N][CHUNK];
  for (int k = 0; k < CHUNKS && g_run; k++) {
    for (int i = 0; i < CHUNK; i++) {
      sn[i] = (uint64_t)(k * CHUNK + i);
      for (int c = 0; c < N; c++) {
        ch[c][i] = c + i * 0.01;
        ct[c][i] = 1;
      }
    }
    void* cols[1 + N + N];
    cols[0] = sn;
    for (int c = 0; c < N; c++) {
      cols[1 + c] = ch[c];
      cols[1 + N + c] = ct[c];
    }
    pthread_mutex_lock(&g_mu);
    if (g_cb) g_cb(cols, CHUNK, g_user);
    pthread_mutex_unlock(&g_mu);
    usleep(100000);
  }
  return NULL;
}

uint8_t ba_core_init(void) { return 0; }
uint8_t ba_core_close(void) { return 0; }
void* ba_eeg_manager_new(void) { return malloc(8); }
void ba_eeg_manager_free(void* m) { free(m); }
uint8_t ba_eeg_manager_connect(void* m, void* name, void* a, void* b) {
  (void)m; (void)name; (void)a; (void)b;
  return 0;
}
void ba_eeg_manager_disconnect(void* m) { (void)m; }
uint8_t ba_eeg_manager_is_connected(void* m) { (void)m; return 1; }
uint8_t ba_eeg_manager_start_stream(void* m, void* a, void* b) {
  (void)m; (void)a; (void)b;
  g_run = 1;
  pthread_t t;
  pthread_create(&t, NULL, run, NULL);
  pthread_detach(t);
  return 0;
}
uint8_t ba_eeg_manager_stop_stream(void* m, void* a, void* b) {
  (void)m; (void)a; (void)b;
  g_run = 0;
  return 0;
}
uint8_t ba_eeg_manager_load_config(void* m, void* a, void* b) {
  (void)m; (void)a; (void)b;
  return 0;
}
void ba_eeg_manager_set_channel_enabled(void* m, uint16_t id, bool en) {
  (void)m; (void)id; (void)en;
}
void ba_eeg_manager_set_channel_bias_feedback(void* m, uint16_t id) {
  (void)m; (void)id;
}
uint8_t ba_eeg_manager_set_data_stream_rate(void* m, uint8_t r) {
  (void)m; (void)r;
  return 0;
}
size_t ba_eeg_manager_get_channel_index(void* m, uint16_t id) {
  (void)m;
  if (id == 0) return 0;
  if (id >= 1025) return 1 + N + (id - 1025);
  return 1 + (id - 1);
}
void* ba_eeg_manager_get_device_info(void* m) {
  (void)m;
  static char info[32];
  return info;
}
void ba_eeg_manager_set_callback_chunk(void* m, void* cb, void* user) {
  (void)m;
  pthread_mutex_lock(&g_mu);
  g_cb = (chunk_cb)cb;
  g_user = user;
  pthread_mutex_unlock(&g_mu);
}
void ba_eeg_manager_set_callback_disconnect(void* m, void* cb, void* user) {
  (void)m; (void)cb; (void)user;
}
void* ba_core_device_features_get(void* info) { return info; }
uint8_t ba_core_device_features_electrode_count(void* f) { (void)f; return N; }
