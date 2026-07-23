#include "gpuc-readonly.h"

static NTSTATUS GpucCopyToRequest(
    _In_ WDFREQUEST Request,
    _In_reads_bytes_(Length) const void* Source,
    _In_ size_t Length
)
{
    void* output = NULL;
    NTSTATUS status = WdfRequestRetrieveOutputBuffer(Request, Length, &output, NULL);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    RtlCopyMemory(output, Source, Length);
    WdfRequestSetInformation(Request, Length);
    return STATUS_SUCCESS;
}

NTSTATUS GpucCreateQueue(_In_ WDFDEVICE Device)
{
    WDF_IO_QUEUE_CONFIG queueConfig;
    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig, WdfIoQueueDispatchSequential);
    queueConfig.EvtIoDeviceControl = GpucEvtIoDeviceControl;

    return WdfIoQueueCreate(
        Device,
        &queueConfig,
        WDF_NO_OBJECT_ATTRIBUTES,
        WDF_NO_HANDLE);
}

void GpucEvtIoDeviceControl(
    _In_ WDFQUEUE Queue,
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength,
    _In_ ULONG IoControlCode
)
{
    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);

    WDFDEVICE device = WdfIoQueueGetDevice(Queue);
    PDEVICE_CONTEXT context = GpucGetDeviceContext(device);
    NTSTATUS status = STATUS_INVALID_DEVICE_REQUEST;

    switch (IoControlCode) {
    case IOCTL_GPUC_GET_VERSION: {
        GPUC_VERSION_INFO version = { 0 };
        version.Version = GPUC_READONLY_VERSION;
        version.MaxResources = GPUC_MAX_RESOURCES;
        version.MaxReadLength = GPUC_MAX_READ_LENGTH;
        status = GpucCopyToRequest(Request, &version, sizeof(version));
        break;
    }

    case IOCTL_GPUC_GET_DEVICE_INFO: {
        GPUC_DEVICE_INFO info = { 0 };
        info.Version = GPUC_READONLY_VERSION;
        RtlStringCchCopyW(info.HardwareId, RTL_NUMBER_OF(info.HardwareId), L"ACPI\\APP000B");
        RtlStringCchCopyW(info.CompatibleId, RTL_NUMBER_OF(info.CompatibleId), L"gpuc");
        RtlStringCchCopyW(info.AcpiPath, RTL_NUMBER_OF(info.AcpiPath), L"reported by firmware; verify in user-mode inspector");
        info.ResourceCount = context->ResourceCount;
        status = GpucCopyToRequest(Request, &info, sizeof(info));
        break;
    }

    case IOCTL_GPUC_GET_RESOURCES: {
        GPUC_RESOURCE_LIST list = { 0 };
        list.Version = GPUC_READONLY_VERSION;
        list.Count = context->ResourceCount;
        for (ULONG i = 0; i < context->ResourceCount && i < GPUC_MAX_RESOURCES; ++i) {
            list.Resources[i].Version = GPUC_READONLY_VERSION;
            list.Resources[i].Index = i;
            list.Resources[i].Type = CmResourceTypeMemory;
            list.Resources[i].RawStart = context->Resources[i].RawStart.QuadPart;
            list.Resources[i].TranslatedStart = context->Resources[i].TranslatedStart.QuadPart;
            list.Resources[i].Length = context->Resources[i].Length;
            list.Resources[i].Flags = context->Resources[i].Flags;
        }
        status = GpucCopyToRequest(Request, &list, sizeof(list));
        break;
    }

    case IOCTL_GPUC_READ_RESOURCE_BYTES: {
#if !defined(GPUC_ENABLE_REPORTED_RESOURCE_READ)
        status = STATUS_NOT_SUPPORTED;
        break;
#else
        GPUC_READ_REQUEST* read = NULL;
        status = WdfRequestRetrieveInputBuffer(Request, sizeof(*read), (void**)&read, NULL);
        if (!NT_SUCCESS(status)) {
            break;
        }

        if (read->Version != GPUC_READONLY_VERSION ||
            read->ResourceIndex >= context->ResourceCount ||
            read->Length == 0 ||
            read->Length > GPUC_MAX_READ_LENGTH) {
            status = STATUS_INVALID_PARAMETER;
            break;
        }

        GPUC_RESOURCE_ENTRY* resource = &context->Resources[read->ResourceIndex];
        if (!resource->Mapped || resource->MappedBase == NULL ||
            read->Offset > resource->Length ||
            read->Length > resource->Length - read->Offset) {
            status = STATUS_INVALID_PARAMETER;
            break;
        }

        GPUC_READ_RESPONSE response = { 0 };
        response.Version = GPUC_READONLY_VERSION;
        response.ResourceIndex = read->ResourceIndex;
        response.Offset = read->Offset;
        response.Length = read->Length;

        for (ULONG i = 0; i < read->Length; ++i) {
            response.Data[i] = READ_REGISTER_UCHAR((PUCHAR)(resource->MappedBase + read->Offset + i));
        }

        status = GpucCopyToRequest(Request, &response, sizeof(response));
        break;
#endif
    }

    case IOCTL_GPUC_GET_NOTIFICATION_COUNTERS:
        status = GpucCopyToRequest(Request, &context->Counters, sizeof(context->Counters));
        break;

    case IOCTL_GPUC_GET_LAST_ERROR_STATE:
        status = GpucCopyToRequest(Request, &context->LastError, sizeof(context->LastError));
        break;

    default:
        status = STATUS_INVALID_DEVICE_REQUEST;
        break;
    }

    if (!NT_SUCCESS(status)) {
        GpucSetLastError(context, status, IoControlCode);
    }

    WdfRequestComplete(Request, status);
}
