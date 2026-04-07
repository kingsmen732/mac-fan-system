#ifndef FAN_BRIDGE_H
#define FAN_BRIDGE_H

#include <stddef.h>

typedef struct {
  char name[32];
  int actualRPM;
  int minRPM;
  int maxRPM;
  int targetRPM;
  int mode;
  int id;
} fan_info_t;

int fan_bridge_open(char *error_buffer, size_t error_buffer_len);
void fan_bridge_close(void);
int fan_bridge_read(fan_info_t *fans, int maxFans, char *error_buffer, size_t error_buffer_len);
int fan_bridge_force_high(char *error_buffer, size_t error_buffer_len);
int fan_bridge_restore_auto(char *error_buffer, size_t error_buffer_len);

#endif
