#ifndef SMC_BRIDGE_H
#define SMC_BRIDGE_H

#include <IOKit/IOKitLib.h>
#include <stdint.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
  char major;
  char minor;
  char build;
  char reserved[1];
  unsigned short release;
} SMCKeyData_vers_t;

typedef struct {
  unsigned short version;
  unsigned short length;
  unsigned int cpuPLimit;
  unsigned int gpuPLimit;
  unsigned int memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
  unsigned int dataSize;
  unsigned int dataType;
  char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
  unsigned int key;
  SMCKeyData_vers_t vers;
  SMCKeyData_pLimitData_t pLimitData;
  SMCKeyData_keyInfo_t keyInfo;
  char result;
  char status;
  char data8;
  unsigned int data32;
  SMCBytes_t bytes;
} SMCKeyData_t;

io_connect_t SMCOpen(void);
kern_return_t SMCClose(io_connect_t conn);
kern_return_t SMCReadKey(io_connect_t conn, const char *key, SMCKeyData_t *val);
double SMCGetFloatValue(io_connect_t conn, const char *key);
int SMCGetKeyCount(io_connect_t conn);
kern_return_t SMCGetKeyFromIndex(io_connect_t conn, int index, char *outputKey);
kern_return_t SMCGetKeyInfo(io_connect_t conn, const char *key, SMCKeyData_keyInfo_t *keyInfo);
kern_return_t SMCWriteKey(io_connect_t conn, const char *key, unsigned int dataType, SMCBytes_t bytes, unsigned int dataSize);
kern_return_t SMCSetFloat(io_connect_t conn, const char *key, float value);
kern_return_t SMCSetUI8(io_connect_t conn, const char *key, uint8_t value);

#endif
