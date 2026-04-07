#include "smc_bridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t key_to_uint(const char *key) {
  return ((uint32_t)key[0] << 24) | ((uint32_t)key[1] << 16) | ((uint32_t)key[2] << 8) |
         (uint32_t)key[3];
}

static kern_return_t smc_call(io_connect_t conn, SMCKeyData_t *input, SMCKeyData_t *output) {
  size_t input_size = sizeof(SMCKeyData_t);
  size_t output_size = sizeof(SMCKeyData_t);
  return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, input, input_size, output, &output_size);
}

static void copy_uint_to_key(uint32_t key, char *outputKey) {
  outputKey[0] = (char)((key >> 24) & 0xff);
  outputKey[1] = (char)((key >> 16) & 0xff);
  outputKey[2] = (char)((key >> 8) & 0xff);
  outputKey[3] = (char)(key & 0xff);
  outputKey[4] = '\0';
}

io_connect_t SMCOpen(void) {
  io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (service == IO_OBJECT_NULL) {
    return 0;
  }

  io_connect_t conn = 0;
  kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &conn);
  IOObjectRelease(service);
  if (result != KERN_SUCCESS) {
    return 0;
  }
  return conn;
}

kern_return_t SMCClose(io_connect_t conn) {
  if (conn == 0) {
    return kIOReturnSuccess;
  }
  return IOServiceClose(conn);
}

kern_return_t SMCGetKeyInfo(io_connect_t conn, const char *key, SMCKeyData_keyInfo_t *keyInfo) {
  if (conn == 0 || key == NULL || keyInfo == NULL) {
    return kIOReturnBadArgument;
  }

  SMCKeyData_t input;
  SMCKeyData_t output;
  memset(&input, 0, sizeof(input));
  memset(&output, 0, sizeof(output));

  input.key = key_to_uint(key);
  input.data8 = SMC_CMD_READ_KEYINFO;

  kern_return_t result = smc_call(conn, &input, &output);
  if (result != KERN_SUCCESS) {
    return result;
  }

  *keyInfo = output.keyInfo;
  return kIOReturnSuccess;
}

kern_return_t SMCReadKey(io_connect_t conn, const char *key, SMCKeyData_t *val) {
  if (conn == 0 || key == NULL || val == NULL) {
    return kIOReturnBadArgument;
  }

  memset(val, 0, sizeof(*val));
  val->key = key_to_uint(key);

  kern_return_t result = SMCGetKeyInfo(conn, key, &val->keyInfo);
  if (result != KERN_SUCCESS) {
    return result;
  }

  SMCKeyData_t input;
  SMCKeyData_t output;
  memset(&input, 0, sizeof(input));
  memset(&output, 0, sizeof(output));

  input.key = key_to_uint(key);
  input.data8 = SMC_CMD_READ_BYTES;
  input.keyInfo.dataSize = val->keyInfo.dataSize;

  result = smc_call(conn, &input, &output);
  if (result != KERN_SUCCESS) {
    return result;
  }

  val->data8 = output.data8;
  val->data32 = output.data32;
  val->result = output.result;
  val->status = output.status;
  memcpy(val->bytes, output.bytes, sizeof(output.bytes));
  return kIOReturnSuccess;
}

double SMCGetFloatValue(io_connect_t conn, const char *key) {
  SMCKeyData_t val;
  if (SMCReadKey(conn, key, &val) != kIOReturnSuccess) {
    return 0.0;
  }

  char type[5];
  copy_uint_to_key(val.keyInfo.dataType, type);

  if (strncmp(type, "flt ", 4) == 0 || strncmp(type, "flt", 3) == 0) {
    float value = 0.0f;
    memcpy(&value, val.bytes, sizeof(float));
    return value;
  }

  if (strncmp(type, "fpe2", 4) == 0) {
    uint16_t fixed = ((uint16_t)(uint8_t)val.bytes[0] << 8) | (uint16_t)(uint8_t)val.bytes[1];
    return (double)fixed / 4.0;
  }

  if (strncmp(type, "ui8 ", 4) == 0 || strncmp(type, "ui8", 3) == 0) {
    return (double)(uint8_t)val.bytes[0];
  }

  return 0.0;
}

int SMCGetKeyCount(io_connect_t conn) {
  SMCKeyData_t val;
  if (SMCReadKey(conn, "#KEY", &val) != kIOReturnSuccess) {
    return 0;
  }
  return (int)(((uint32_t)(uint8_t)val.bytes[0] << 24) | ((uint32_t)(uint8_t)val.bytes[1] << 16) |
               ((uint32_t)(uint8_t)val.bytes[2] << 8) | (uint32_t)(uint8_t)val.bytes[3]);
}

kern_return_t SMCGetKeyFromIndex(io_connect_t conn, int index, char *outputKey) {
  if (conn == 0 || outputKey == NULL || index < 0) {
    return kIOReturnBadArgument;
  }

  SMCKeyData_t input;
  SMCKeyData_t output;
  memset(&input, 0, sizeof(input));
  memset(&output, 0, sizeof(output));

  input.data8 = SMC_CMD_READ_INDEX;
  input.data32 = (uint32_t)index;

  kern_return_t result = smc_call(conn, &input, &output);
  if (result != KERN_SUCCESS) {
    return result;
  }

  copy_uint_to_key(output.key, outputKey);
  return kIOReturnSuccess;
}

kern_return_t SMCWriteKey(io_connect_t conn, const char *key, unsigned int dataType, SMCBytes_t bytes,
                          unsigned int dataSize) {
  if (conn == 0 || key == NULL || bytes == NULL) {
    return kIOReturnBadArgument;
  }

  SMCKeyData_t input;
  SMCKeyData_t output;
  memset(&input, 0, sizeof(input));
  memset(&output, 0, sizeof(output));

  input.key = key_to_uint(key);
  input.data8 = SMC_CMD_WRITE_BYTES;
  input.keyInfo.dataType = dataType;
  input.keyInfo.dataSize = dataSize;
  memcpy(input.bytes, bytes, sizeof(input.bytes));

  return smc_call(conn, &input, &output);
}

kern_return_t SMCSetFloat(io_connect_t conn, const char *key, float value) {
  SMCKeyData_keyInfo_t keyInfo;
  kern_return_t result = SMCGetKeyInfo(conn, key, &keyInfo);
  if (result != kIOReturnSuccess) {
    return result;
  }

  SMCBytes_t bytes;
  memset(bytes, 0, sizeof(bytes));
  memcpy(bytes, &value, sizeof(float));
  return SMCWriteKey(conn, key, keyInfo.dataType, bytes, keyInfo.dataSize);
}

kern_return_t SMCSetUI8(io_connect_t conn, const char *key, uint8_t value) {
  SMCKeyData_keyInfo_t keyInfo;
  kern_return_t result = SMCGetKeyInfo(conn, key, &keyInfo);
  if (result != kIOReturnSuccess) {
    return result;
  }

  SMCBytes_t bytes;
  memset(bytes, 0, sizeof(bytes));
  bytes[0] = (char)value;
  return SMCWriteKey(conn, key, keyInfo.dataType, bytes, keyInfo.dataSize);
}
