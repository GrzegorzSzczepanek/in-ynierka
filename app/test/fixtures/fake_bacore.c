#include <pthread.h>
#include <stdlib.h>
#include <stddef.h>
#include <unistd.h>
typedef void (*cb_t)(const void* const*, size_t, void*);
typedef struct { cb_t cb; } arg_t;
static void* run(void* p) {
  arg_t* a = (arg_t*)p;
  for (int n = 0; n < 5; n++) {
    size_t sn[25]; double ch[25];
    for (int i = 0; i < 25; i++) { sn[i] = n * 25 + i; ch[i] = n + i * 0.01; }
    const void* cols[2] = { sn, ch };
    a->cb(cols, 25, NULL);
    usleep(20000);
  }
  return NULL;
}
void fire(cb_t cb) {
  arg_t* a = malloc(sizeof(arg_t)); a->cb = cb;
  pthread_t t; pthread_create(&t, NULL, run, a); pthread_detach(t);
}
