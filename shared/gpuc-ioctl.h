#pragma once

#define GPUC_READONLY_VERSION 1u
#define GPUC_MAX_RESOURCES 8u
#define GPUC_MAX_READ_LENGTH 256u
#define GPUC_DEVICE_PATH_NAME L"\\\\.\\GpucReadonly"

// {D17B7593-CE21-4DC8-93CC-6F6658F6DA86}
// Private lab interface GUID. This is not a public Windows device class.
DEFINE_GUID(GUID_DEVINTERFACE_GPUC_READONLY,
    0xd17b7593, 0xce21, 0x4dc8, 0x93, 0xcc, 0x6f, 0x66, 0x58, 0xf6, 0xda, 0x86);

#define FILE_DEVICE_GPUC_READONLY 0x8337u

#define IOCTL_GPUC_GET_VERSION \
    CTL_CODE(FILE_DEVICE_GPUC_READONLY, 0x800, METHOD_BUFFERED, FILE_READ_DATA)

#define IOCTL_GPUC_GET_DEVICE_INFO \
    CTL_CODE(FILE_DEVICE_GPUC_READONLY, 0x801, METHOD_BUFFERED, FILE_READ_DATA)

#define IOCTL_GPUC_GET_RESOURCES \
    CTL_CODE(FILE_DEVICE_GPUC_READONLY, 0x802, METHOD_BUFFERED, FILE_READ_DATA)

#define IOCTL_GPUC_READ_RESOURCE_BYTES \
    CTL_CODE(FILE_DEVICE_GPUC_READONLY, 0x803, METHOD_BUFFERED, FILE_READ_DATA)

#define IOCTL_GPUC_GET_NOTIFICATION_COUNTERS \
    CTL_CODE(FILE_DEVICE_GPUC_READONLY, 0x804, METHOD_BUFFERED, FILE_READ_DATA)

#define IOCTL_GPUC_GET_LAST_ERROR_STATE \
    CTL_CODE(FILE_DEVICE_GPUC_READONLY, 0x805, METHOD_BUFFERED, FILE_READ_DATA)

typedef struct _GPUC_VERSION_INFO {
    unsigned int Version;
    unsigned int MaxResources;
    unsigned int MaxReadLength;
    unsigned int Flags;
} GPUC_VERSION_INFO;

typedef struct _GPUC_DEVICE_INFO {
    unsigned int Version;
    wchar_t HardwareId[64];
    wchar_t CompatibleId[64];
    wchar_t AcpiPath[128];
    unsigned int ResourceCount;
    unsigned int Flags;
} GPUC_DEVICE_INFO;

typedef struct _GPUC_RESOURCE_INFO {
    unsigned int Version;
    unsigned int Index;
    unsigned int Type;
    unsigned int Flags;
    unsigned long long RawStart;
    unsigned long long TranslatedStart;
    unsigned long long Length;
} GPUC_RESOURCE_INFO;

typedef struct _GPUC_RESOURCE_LIST {
    unsigned int Version;
    unsigned int Count;
    GPUC_RESOURCE_INFO Resources[GPUC_MAX_RESOURCES];
} GPUC_RESOURCE_LIST;

typedef struct _GPUC_READ_REQUEST {
    unsigned int Version;
    unsigned int ResourceIndex;
    unsigned int Offset;
    unsigned int Length;
} GPUC_READ_REQUEST;

typedef struct _GPUC_READ_RESPONSE {
    unsigned int Version;
    unsigned int ResourceIndex;
    unsigned int Offset;
    unsigned int Length;
    unsigned char Data[GPUC_MAX_READ_LENGTH];
} GPUC_READ_RESPONSE;

typedef struct _GPUC_NOTIFICATION_COUNTERS {
    unsigned int Version;
    unsigned int PrepareHardwareCount;
    unsigned int ReleaseHardwareCount;
    unsigned int D0EntryCount;
    unsigned int D0ExitCount;
    unsigned int Reserved;
} GPUC_NOTIFICATION_COUNTERS;

typedef struct _GPUC_LAST_ERROR_STATE {
    unsigned int Version;
    long LastNtStatus;
    unsigned int LastOperation;
    unsigned int Reserved;
} GPUC_LAST_ERROR_STATE;
