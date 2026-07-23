#include <windows.h>
#include <initguid.h>
#include <setupapi.h>

#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "..\..\shared\gpuc-ioctl.h"

namespace {

std::wstring FormatError(DWORD error) {
    wchar_t* buffer = nullptr;
    DWORD size = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        error,
        0,
        reinterpret_cast<LPWSTR>(&buffer),
        0,
        nullptr);

    std::wstring result = size ? std::wstring(buffer, size) : L"unknown error";
    if (buffer) LocalFree(buffer);
    while (!result.empty() && (result.back() == L'\n' || result.back() == L'\r')) {
        result.pop_back();
    }
    return result;
}

std::wstring Hex(unsigned long long value) {
    std::wstringstream stream;
    stream << L"0x" << std::uppercase << std::hex << std::setw(8) << std::setfill(L'0') << value;
    return stream.str();
}

HANDLE OpenGpucInterface() {
    HDEVINFO info = SetupDiGetClassDevsW(
        &GUID_DEVINTERFACE_GPUC_READONLY,
        nullptr,
        nullptr,
        DIGCF_DEVICEINTERFACE | DIGCF_PRESENT);
    if (info == INVALID_HANDLE_VALUE) {
        return INVALID_HANDLE_VALUE;
    }

    SP_DEVICE_INTERFACE_DATA interfaceData{};
    interfaceData.cbSize = sizeof(interfaceData);
    if (!SetupDiEnumDeviceInterfaces(info, nullptr, &GUID_DEVINTERFACE_GPUC_READONLY, 0, &interfaceData)) {
        const DWORD error = GetLastError();
        SetupDiDestroyDeviceInfoList(info);
        SetLastError(error == ERROR_NO_MORE_ITEMS ? ERROR_NOT_FOUND : error);
        return INVALID_HANDLE_VALUE;
    }

    DWORD required = 0;
    SetupDiGetDeviceInterfaceDetailW(info, &interfaceData, nullptr, 0, &required, nullptr);
    if (required == 0) {
        const DWORD error = GetLastError();
        SetupDiDestroyDeviceInfoList(info);
        SetLastError(error == ERROR_SUCCESS ? ERROR_NOT_FOUND : error);
        return INVALID_HANDLE_VALUE;
    }

    std::vector<BYTE> buffer(required);
    auto* detail = reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buffer.data());
    detail->cbSize = sizeof(*detail);
    if (!SetupDiGetDeviceInterfaceDetailW(info, &interfaceData, detail, required, nullptr, nullptr)) {
        const DWORD error = GetLastError();
        SetupDiDestroyDeviceInfoList(info);
        SetLastError(error);
        return INVALID_HANDLE_VALUE;
    }

    HANDLE handle = CreateFileW(
        detail->DevicePath,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);

    SetupDiDestroyDeviceInfoList(info);
    return handle;
}

template <typename T>
bool IoctlOut(HANDLE device, DWORD code, T& output) {
    DWORD returned = 0;
    return DeviceIoControl(
        device,
        code,
        nullptr,
        0,
        &output,
        sizeof(output),
        &returned,
        nullptr) != FALSE;
}

void PrintUsage() {
    std::wcout << L"GPUC KMDF client scaffold\n\n";
    std::wcout << L"Usage:\n";
    std::wcout << L"  gpuc-kmdf-client.exe --version\n";
    std::wcout << L"  gpuc-kmdf-client.exe --resources\n";
    std::wcout << L"\nPhase 1 has no automatic resource reads.\n";
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    bool showVersion = false;
    bool showResources = false;

    for (int i = 1; i < argc; ++i) {
        const std::wstring arg = argv[i];
        if (arg == L"--version") showVersion = true;
        if (arg == L"--resources") showResources = true;
    }

    if (!showVersion && !showResources) {
        PrintUsage();
        return 0;
    }

    HANDLE device = OpenGpucInterface();
    if (device == INVALID_HANDLE_VALUE) {
        std::wcerr << L"GPUC read-only device interface not found: " << FormatError(GetLastError()) << L"\n";
        std::wcerr << L"This is expected until the KMDF probe is built and installed in a controlled test environment.\n";
        return 2;
    }

    if (showVersion) {
        GPUC_VERSION_INFO version{};
        if (IoctlOut(device, IOCTL_GPUC_GET_VERSION, version)) {
            std::wcout << L"Version: " << version.Version << L"\n";
            std::wcout << L"MaxResources: " << version.MaxResources << L"\n";
            std::wcout << L"MaxReadLength: " << version.MaxReadLength << L"\n";
        } else {
            std::wcerr << L"IOCTL_GPUC_GET_VERSION failed: " << FormatError(GetLastError()) << L"\n";
        }
    }

    if (showResources) {
        GPUC_RESOURCE_LIST resources{};
        if (IoctlOut(device, IOCTL_GPUC_GET_RESOURCES, resources)) {
            std::wcout << L"Resources: " << resources.Count << L"\n";
            for (unsigned int i = 0; i < resources.Count && i < GPUC_MAX_RESOURCES; ++i) {
                const auto& resource = resources.Resources[i];
                std::wcout << L"- index " << resource.Index
                    << L" raw=" << Hex(resource.RawStart)
                    << L" translated=" << Hex(resource.TranslatedStart)
                    << L" length=" << resource.Length << L"\n";
            }
        } else {
            std::wcerr << L"IOCTL_GPUC_GET_RESOURCES failed: " << FormatError(GetLastError()) << L"\n";
        }
    }

    CloseHandle(device);
    return 0;
}
