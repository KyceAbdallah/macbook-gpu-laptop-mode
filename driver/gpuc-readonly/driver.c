#include "gpuc-readonly.h"

#include <initguid.h>

void GpucSetLastError(
    _In_ PDEVICE_CONTEXT Context,
    _In_ NTSTATUS Status,
    _In_ ULONG Operation
)
{
    Context->LastError.Version = GPUC_READONLY_VERSION;
    Context->LastError.LastNtStatus = Status;
    Context->LastError.LastOperation = Operation;
}

NTSTATUS DriverEntry(
    _In_ PDRIVER_OBJECT DriverObject,
    _In_ PUNICODE_STRING RegistryPath
)
{
    WDF_DRIVER_CONFIG config;
    WDF_DRIVER_CONFIG_INIT(&config, GpucEvtDeviceAdd);

    return WdfDriverCreate(
        DriverObject,
        RegistryPath,
        WDF_NO_OBJECT_ATTRIBUTES,
        &config,
        WDF_NO_HANDLE);
}

NTSTATUS GpucEvtDeviceAdd(
    _In_ WDFDRIVER Driver,
    _Inout_ PWDFDEVICE_INIT DeviceInit
)
{
    UNREFERENCED_PARAMETER(Driver);

    WdfDeviceInitSetDeviceType(DeviceInit, FILE_DEVICE_GPUC_READONLY);
    WdfDeviceInitSetIoType(DeviceInit, WdfDeviceIoBuffered);

    WDF_OBJECT_ATTRIBUTES attributes;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attributes, DEVICE_CONTEXT);

    WDF_PNPPOWER_EVENT_CALLBACKS pnpPowerCallbacks;
    WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&pnpPowerCallbacks);
    pnpPowerCallbacks.EvtDevicePrepareHardware = GpucEvtDevicePrepareHardware;
    pnpPowerCallbacks.EvtDeviceReleaseHardware = GpucEvtDeviceReleaseHardware;
    pnpPowerCallbacks.EvtDeviceD0Entry = GpucEvtDeviceD0Entry;
    pnpPowerCallbacks.EvtDeviceD0Exit = GpucEvtDeviceD0Exit;
    WdfDeviceInitSetPnpPowerEventCallbacks(DeviceInit, &pnpPowerCallbacks);

    WDFDEVICE device;
    NTSTATUS status = WdfDeviceCreate(&DeviceInit, &attributes, &device);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    PDEVICE_CONTEXT context = GpucGetDeviceContext(device);
    RtlZeroMemory(context, sizeof(*context));
    context->Device = device;
    context->Counters.Version = GPUC_READONLY_VERSION;
    context->LastError.Version = GPUC_READONLY_VERSION;

    status = WdfDeviceCreateDeviceInterface(
        device,
        &GUID_DEVINTERFACE_GPUC_READONLY,
        NULL);
    if (!NT_SUCCESS(status)) {
        GpucSetLastError(context, status, IOCTL_GPUC_GET_DEVICE_INFO);
        return status;
    }

    status = GpucCreateQueue(device);
    if (!NT_SUCCESS(status)) {
        GpucSetLastError(context, status, IOCTL_GPUC_GET_DEVICE_INFO);
    }

    return status;
}

NTSTATUS GpucEvtDevicePrepareHardware(
    _In_ WDFDEVICE Device,
    _In_ WDFCMRESLIST ResourcesRaw,
    _In_ WDFCMRESLIST ResourcesTranslated
)
{
    PDEVICE_CONTEXT context = GpucGetDeviceContext(Device);
    context->Counters.PrepareHardwareCount++;
    context->ResourceCount = 0;

    const ULONG rawCount = WdfCmResourceListGetCount(ResourcesRaw);
    const ULONG translatedCount = WdfCmResourceListGetCount(ResourcesTranslated);
    const ULONG count = rawCount < translatedCount ? rawCount : translatedCount;

    for (ULONG i = 0; i < count && context->ResourceCount < GPUC_MAX_RESOURCES; ++i) {
        PCM_PARTIAL_RESOURCE_DESCRIPTOR raw = WdfCmResourceListGetDescriptor(ResourcesRaw, i);
        PCM_PARTIAL_RESOURCE_DESCRIPTOR translated = WdfCmResourceListGetDescriptor(ResourcesTranslated, i);
        if (raw == NULL || translated == NULL) {
            continue;
        }

        if (translated->Type != CmResourceTypeMemory) {
            continue;
        }

        GPUC_RESOURCE_ENTRY* entry = &context->Resources[context->ResourceCount++];
        RtlZeroMemory(entry, sizeof(*entry));
        entry->RawStart = raw->u.Memory.Start;
        entry->TranslatedStart = translated->u.Memory.Start;
        entry->Length = translated->u.Memory.Length;

        // Phase 1 maps only resources Windows assigned to this device.
        entry->MappedBase = (volatile UCHAR*)MmMapIoSpaceEx(
            entry->TranslatedStart,
            entry->Length,
            PAGE_READONLY | PAGE_NOCACHE);
        if (entry->MappedBase == NULL) {
            entry->Mapped = FALSE;
            GpucSetLastError(context, STATUS_INSUFFICIENT_RESOURCES, 1);
            continue;
        }

        entry->Mapped = TRUE;
    }

    return STATUS_SUCCESS;
}

NTSTATUS GpucEvtDeviceReleaseHardware(
    _In_ WDFDEVICE Device,
    _In_ WDFCMRESLIST ResourcesTranslated
)
{
    UNREFERENCED_PARAMETER(ResourcesTranslated);

    PDEVICE_CONTEXT context = GpucGetDeviceContext(Device);
    context->Counters.ReleaseHardwareCount++;

    for (ULONG i = 0; i < context->ResourceCount; ++i) {
        GPUC_RESOURCE_ENTRY* entry = &context->Resources[i];
        if (entry->Mapped && entry->MappedBase != NULL) {
            MmUnmapIoSpace((PVOID)entry->MappedBase, entry->Length);
            entry->Mapped = FALSE;
            entry->MappedBase = NULL;
        }
    }

    context->ResourceCount = 0;
    return STATUS_SUCCESS;
}

NTSTATUS GpucEvtDeviceD0Entry(
    _In_ WDFDEVICE Device,
    _In_ WDF_POWER_DEVICE_STATE PreviousState
)
{
    UNREFERENCED_PARAMETER(PreviousState);
    GpucGetDeviceContext(Device)->Counters.D0EntryCount++;
    return STATUS_SUCCESS;
}

NTSTATUS GpucEvtDeviceD0Exit(
    _In_ WDFDEVICE Device,
    _In_ WDF_POWER_DEVICE_STATE TargetState
)
{
    UNREFERENCED_PARAMETER(TargetState);
    GpucGetDeviceContext(Device)->Counters.D0ExitCount++;
    return STATUS_SUCCESS;
}
