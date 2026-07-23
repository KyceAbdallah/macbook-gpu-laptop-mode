#pragma once

#include <ntddk.h>
#include <ntstrsafe.h>
#include <wdf.h>

#include "..\..\shared\gpuc-ioctl.h"

#define GPUC_POOL_TAG 'cpUG'

typedef struct _GPUC_RESOURCE_ENTRY {
    PHYSICAL_ADDRESS RawStart;
    PHYSICAL_ADDRESS TranslatedStart;
    SIZE_T Length;
    BOOLEAN Mapped;
    volatile UCHAR* MappedBase;
} GPUC_RESOURCE_ENTRY;

typedef struct _DEVICE_CONTEXT {
    WDFDEVICE Device;
    ULONG ResourceCount;
    GPUC_RESOURCE_ENTRY Resources[GPUC_MAX_RESOURCES];
    GPUC_NOTIFICATION_COUNTERS Counters;
    GPUC_LAST_ERROR_STATE LastError;
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GpucGetDeviceContext);

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD GpucEvtDeviceAdd;
EVT_WDF_DEVICE_PREPARE_HARDWARE GpucEvtDevicePrepareHardware;
EVT_WDF_DEVICE_RELEASE_HARDWARE GpucEvtDeviceReleaseHardware;
EVT_WDF_DEVICE_D0_ENTRY GpucEvtDeviceD0Entry;
EVT_WDF_DEVICE_D0_EXIT GpucEvtDeviceD0Exit;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL GpucEvtIoDeviceControl;

NTSTATUS GpucCreateQueue(_In_ WDFDEVICE Device);

void GpucSetLastError(
    _In_ PDEVICE_CONTEXT Context,
    _In_ NTSTATUS Status,
    _In_ ULONG Operation
);
