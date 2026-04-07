#include "fan_bridge.h"
#include "smc_bridge.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;
extern CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup,
                                                   uint64_t a, uint64_t b, uint64_t c);
extern void IOReportMergeChannels(CFDictionaryRef a, CFDictionaryRef b, CFTypeRef unused);
extern IOReportSubscriptionRef IOReportCreateSubscription(void *a, CFMutableDictionaryRef channels,
                                                          CFMutableDictionaryRef *out, uint64_t d,
                                                          CFTypeRef e);
extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub,
                                             CFMutableDictionaryRef channels, CFTypeRef unused);
extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef a, CFDictionaryRef b,
                                                  CFTypeRef unused);
extern int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef item, int32_t idx);
extern CFStringRef IOReportChannelGetGroup(CFDictionaryRef item);

static IOReportSubscriptionRef g_subscription = NULL;
static CFMutableDictionaryRef g_channels = NULL;
static io_connect_t g_smcConn = 0;
static CFDictionaryRef g_prevSample = NULL;

static int cfStringMatch(CFStringRef str, const char *match) {
  if (str == NULL || match == NULL) return 0;
  CFStringRef matchStr = CFStringCreateWithCString(kCFAllocatorDefault, match, kCFStringEncodingUTF8);
  if (matchStr == NULL) return 0;
  int result = (CFStringCompare(str, matchStr, 0) == kCFCompareEqualTo);
  CFRelease(matchStr);
  return result;
}

static int init_io_report(void) {
  if (g_channels != NULL) {
    return 0;
  }

  CFStringRef energyGroup = CFSTR("Energy Model");
  CFStringRef gpuGroup = CFSTR("GPU Stats");
  CFStringRef cpuGroup = CFSTR("CPU Stats");
  CFStringRef amcGroup = CFSTR("AMC Stats");

  CFDictionaryRef energyChan = IOReportCopyChannelsInGroup(energyGroup, NULL, 0, 0, 0);
  CFDictionaryRef gpuChan = IOReportCopyChannelsInGroup(gpuGroup, NULL, 0, 0, 0);
  if (energyChan == NULL) {
    return -1;
  }
  if (gpuChan != NULL) {
    IOReportMergeChannels(energyChan, gpuChan, NULL);
    CFRelease(gpuChan);
  }
  CFDictionaryRef cpuChan = IOReportCopyChannelsInGroup(cpuGroup, NULL, 0, 0, 0);
  if (cpuChan != NULL) {
    IOReportMergeChannels(energyChan, cpuChan, NULL);
    CFRelease(cpuChan);
  }
  CFDictionaryRef amcChan = IOReportCopyChannelsInGroup(amcGroup, NULL, 0, 0, 0);
  if (amcChan != NULL) {
    IOReportMergeChannels(energyChan, amcChan, NULL);
    CFRelease(amcChan);
  }

  CFDictionaryRef pmpChan = IOReportCopyChannelsInGroup(CFSTR("PMP"), NULL, 0, 0, 0);
  if (pmpChan != NULL) {
    IOReportMergeChannels(energyChan, pmpChan, NULL);
    CFRelease(pmpChan);
  }

  CFIndex size = CFDictionaryGetCount(energyChan);
  g_channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, size, energyChan);
  CFRelease(energyChan);
  if (g_channels == NULL) {
    return -2;
  }

  g_subscription = IOReportCreateSubscription(NULL, g_channels, NULL, 0, NULL);
  if (g_subscription == NULL) {
    CFRelease(g_channels);
    g_channels = NULL;
    return -3;
  }

  if (g_smcConn == 0) {
    g_smcConn = SMCOpen();
  }

  g_prevSample = IOReportCreateSamples(g_subscription, g_channels, NULL);
  if (g_prevSample == NULL) {
    return -4;
  }
  usleep(100000);
  return 0;
}

static void pump_io_report(void) {
  if (g_subscription == NULL || g_channels == NULL || g_prevSample == NULL) {
    return;
  }

  CFDictionaryRef current = IOReportCreateSamples(g_subscription, g_channels, NULL);
  if (current == NULL) {
    return;
  }

  CFDictionaryRef delta = IOReportCreateSamplesDelta(g_prevSample, current, NULL);
  if (delta != NULL) {
    CFArrayRef arr = CFDictionaryGetValue(delta, CFSTR("IOReportChannels"));
    CFIndex cnt = arr ? CFArrayGetCount(arr) : 0;
    for (CFIndex i = 0; i < cnt; i++) {
      CFDictionaryRef ch = (CFDictionaryRef)CFArrayGetValueAtIndex(arr, i);
      CFStringRef grp = IOReportChannelGetGroup(ch);
      if (!grp) {
        continue;
      }
      if (cfStringMatch(grp, "AMC Stats") || cfStringMatch(grp, "PMP")) {
        (void)IOReportSimpleGetIntegerValue(ch, 0);
      }
    }
    CFRelease(delta);
  }

  CFRelease(g_prevSample);
  g_prevSample = current;
}

static int read_fan_info(fan_info_t *fans, int maxFans) {
  if (!g_smcConn) return 0;

  pump_io_report();

  SMCKeyData_t val;
  if (SMCReadKey(g_smcConn, "FNum", &val) != kIOReturnSuccess) return 0;

  int fanCount = (unsigned char)val.bytes[0];
  if (fanCount > maxFans) fanCount = maxFans;

  for (int i = 0; i < fanCount; i++) {
    char key[5];
    fans[i].id = i;

    snprintf(key, sizeof(key), "F%dAc", i);
    fans[i].actualRPM = (int)SMCGetFloatValue(g_smcConn, key);

    snprintf(key, sizeof(key), "F%dMn", i);
    fans[i].minRPM = (int)SMCGetFloatValue(g_smcConn, key);

    snprintf(key, sizeof(key), "F%dMx", i);
    fans[i].maxRPM = (int)SMCGetFloatValue(g_smcConn, key);

    snprintf(key, sizeof(key), "F%dTg", i);
    fans[i].targetRPM = (int)SMCGetFloatValue(g_smcConn, key);

    snprintf(key, sizeof(key), "F%dMd", i);
    fans[i].mode = (int)SMCGetFloatValue(g_smcConn, key);

    snprintf(fans[i].name, sizeof(fans[i].name), "Fan %d", i);
  }

  return fanCount;
}

int fan_bridge_open(char *error_buffer, size_t error_buffer_len) {
  if (!g_smcConn) {
    g_smcConn = SMCOpen();
  }
  if (!g_smcConn) {
    snprintf(error_buffer, error_buffer_len, "SMCOpen failed");
    return -1;
  }

  // Mirror mactop's broader runtime setup when available, but do not block
  // fan reads if IOReport subscription creation is unavailable on this host.
  (void)init_io_report();
  return 0;
}

void fan_bridge_close(void) {
  if (g_prevSample != NULL) {
    CFRelease(g_prevSample);
    g_prevSample = NULL;
  }
  if (g_channels != NULL) {
    CFRelease(g_channels);
    g_channels = NULL;
  }
  g_subscription = NULL;
  if (g_smcConn) {
    SMCClose(g_smcConn);
    g_smcConn = 0;
  }
}

int fan_bridge_read(fan_info_t *fans, int maxFans, char *error_buffer, size_t error_buffer_len) {
  if (!g_smcConn) {
    snprintf(error_buffer, error_buffer_len, "bridge not open");
    return -1;
  }
  int count = read_fan_info(fans, maxFans);
  if (count <= 0) {
    snprintf(error_buffer, error_buffer_len, "no fan data");
    return -1;
  }
  return count;
}

int fan_bridge_force_high(char *error_buffer, size_t error_buffer_len) {
  if (!g_smcConn) {
    snprintf(error_buffer, error_buffer_len, "bridge not open");
    return -1;
  }

  SMCKeyData_t val;
  if (SMCReadKey(g_smcConn, "FNum", &val) != kIOReturnSuccess) {
    snprintf(error_buffer, error_buffer_len, "failed to read FNum");
    return -1;
  }

  int fanCount = (unsigned char)val.bytes[0];
  for (int i = 0; i < fanCount; i++) {
    char key[5];

    snprintf(key, sizeof(key), "F%dMd", i);
    if (SMCSetUI8(g_smcConn, key, 1) != kIOReturnSuccess) {
      snprintf(error_buffer, error_buffer_len, "failed to set fan %d mode to manual", i);
      return -1;
    }

    snprintf(key, sizeof(key), "F%dMx", i);
    float maxRPM = (float)SMCGetFloatValue(g_smcConn, key);
    if (maxRPM <= 0.0f) {
      snprintf(error_buffer, error_buffer_len, "failed to read max RPM for fan %d", i);
      return -1;
    }

    snprintf(key, sizeof(key), "F%dTg", i);
    if (SMCSetFloat(g_smcConn, key, maxRPM) != kIOReturnSuccess) {
      snprintf(error_buffer, error_buffer_len, "failed to set target RPM for fan %d", i);
      return -1;
    }
  }

  return fanCount;
}

int fan_bridge_restore_auto(char *error_buffer, size_t error_buffer_len) {
  if (!g_smcConn) {
    snprintf(error_buffer, error_buffer_len, "bridge not open");
    return -1;
  }

  SMCKeyData_t val;
  if (SMCReadKey(g_smcConn, "FNum", &val) != kIOReturnSuccess) {
    snprintf(error_buffer, error_buffer_len, "failed to read FNum");
    return -1;
  }

  int fanCount = (unsigned char)val.bytes[0];
  for (int i = 0; i < fanCount; i++) {
    char key[5];
    snprintf(key, sizeof(key), "F%dMd", i);
    if (SMCSetUI8(g_smcConn, key, 0) != kIOReturnSuccess) {
      snprintf(error_buffer, error_buffer_len, "failed to restore auto mode for fan %d", i);
      return -1;
    }
  }

  return fanCount;
}
