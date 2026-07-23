#include <windows.h>
#include <cfgmgr32.h>
#include <initguid.h>
#include <devpkey.h>
#include <setupapi.h>

#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

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
    if (buffer) {
        LocalFree(buffer);
    }
    while (!result.empty() && (result.back() == L'\n' || result.back() == L'\r')) {
        result.pop_back();
    }
    return result;
}

std::wstring HexUnsignedLongLong(unsigned long long value) {
    std::wstringstream stream;
    stream << L"0x" << std::uppercase << std::hex << std::setw(8) << std::setfill(L'0') << value;
    return stream.str();
}

std::wstring GetDevicePropertyString(HDEVINFO info, SP_DEVINFO_DATA& data, const DEVPROPKEY& key) {
    DEVPROPTYPE type = 0;
    DWORD size = 0;
    SetupDiGetDevicePropertyW(info, &data, &key, &type, nullptr, 0, &size, 0);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || size == 0) {
        return L"";
    }

    std::vector<BYTE> buffer(size);
    if (!SetupDiGetDevicePropertyW(info, &data, &key, &type, buffer.data(), size, nullptr, 0)) {
        return L"";
    }

    if (type == DEVPROP_TYPE_STRING) {
        return reinterpret_cast<wchar_t*>(buffer.data());
    }

    if (type == DEVPROP_TYPE_STRING_LIST) {
        const wchar_t* current = reinterpret_cast<wchar_t*>(buffer.data());
        std::wstring joined;
        while (*current) {
            if (!joined.empty()) {
                joined += L", ";
            }
            joined += current;
            current += wcslen(current) + 1;
        }
        return joined;
    }

    return L"";
}

std::wstring GetRegistryPropertyString(HDEVINFO info, SP_DEVINFO_DATA& data, DWORD property) {
    DWORD type = 0;
    DWORD size = 0;
    SetupDiGetDeviceRegistryPropertyW(info, &data, property, &type, nullptr, 0, &size);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || size == 0) {
        return L"";
    }

    std::vector<BYTE> buffer(size);
    if (!SetupDiGetDeviceRegistryPropertyW(info, &data, property, &type, buffer.data(), size, nullptr)) {
        return L"";
    }

    if (type == REG_SZ) {
        return reinterpret_cast<wchar_t*>(buffer.data());
    }

    if (type == REG_MULTI_SZ) {
        const wchar_t* current = reinterpret_cast<wchar_t*>(buffer.data());
        std::wstring joined;
        while (*current) {
            if (!joined.empty()) {
                joined += L", ";
            }
            joined += current;
            current += wcslen(current) + 1;
        }
        return joined;
    }

    return L"";
}

std::wstring GetInstanceId(HDEVINFO info, SP_DEVINFO_DATA& data) {
    DWORD size = 0;
    SetupDiGetDeviceInstanceIdW(info, &data, nullptr, 0, &size);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || size == 0) {
        return L"";
    }

    std::vector<wchar_t> buffer(size);
    if (!SetupDiGetDeviceInstanceIdW(info, &data, buffer.data(), size, nullptr)) {
        return L"";
    }
    return buffer.data();
}

bool ContainsCaseInsensitive(const std::wstring& value, const std::wstring& needle) {
    auto lowerValue = value;
    auto lowerNeedle = needle;
    CharLowerBuffW(lowerValue.data(), static_cast<DWORD>(lowerValue.size()));
    CharLowerBuffW(lowerNeedle.data(), static_cast<DWORD>(lowerNeedle.size()));
    return lowerValue.find(lowerNeedle) != std::wstring::npos;
}

void PrintAllocatedResources(DEVINST devInst) {
    LOG_CONF logConf = 0;
    CONFIGRET cr = CM_Get_First_Log_Conf(&logConf, devInst, ALLOC_LOG_CONF);
    if (cr != CR_SUCCESS) {
        std::wcout << L"  resources: none from CM_Get_Alloc_Log_Conf (CR=" << cr << L")\n";
        return;
    }

    RES_DES resDes = 0;
    RESOURCEID resourceId = ResType_All;
    cr = CM_Get_Next_Res_Des(&resDes, logConf, ResType_All, &resourceId, 0);
    if (cr != CR_SUCCESS) {
        std::wcout << L"  resources: none (CR=" << cr << L")\n";
        CM_Free_Log_Conf_Handle(logConf);
        return;
    }

    while (cr == CR_SUCCESS) {
        ULONG size = 0;
        if (CM_Get_Res_Des_Data_Size(&size, resDes, 0) == CR_SUCCESS && size > 0) {
            std::vector<BYTE> data(size);
            if (CM_Get_Res_Des_Data(resDes, data.data(), size, 0) == CR_SUCCESS) {
                if (resourceId == ResType_Mem && size >= sizeof(MEM_RESOURCE)) {
                    auto* mem = reinterpret_cast<MEM_RESOURCE*>(data.data());
                    std::wcout << L"  memory: "
                               << HexUnsignedLongLong(mem->MEM_Header.MD_Alloc_Base)
                               << L"-"
                               << HexUnsignedLongLong(mem->MEM_Header.MD_Alloc_End)
                               << L"\n";
                    for (ULONG i = 0; i < mem->MEM_Header.MD_Count; ++i) {
                        const auto& range = mem->MEM_Data[i];
                        std::wcout << L"  memoryRequirement: "
                                   << HexUnsignedLongLong(range.MR_Min)
                                   << L"-"
                                   << HexUnsignedLongLong(range.MR_Max)
                                   << L" bytes="
                                   << range.MR_nBytes
                                   << L"\n";
                    }
                } else {
                    std::wcout << L"  resource type " << resourceId << L": " << size << L" bytes\n";
                }
            }
        }

        RES_DES next = 0;
        RESOURCEID nextResourceId = ResType_All;
        CONFIGRET nextCr = CM_Get_Next_Res_Des(&next, resDes, ResType_All, &nextResourceId, 0);
        CM_Free_Res_Des_Handle(resDes);
        resDes = next;
        resourceId = nextResourceId;
        cr = nextCr;
    }

    CM_Free_Log_Conf_Handle(logConf);
}

void PrintDisplayDevices() {
    std::wcout << L"# Display Devices\n";
    DISPLAY_DEVICEW device{};
    device.cb = sizeof(device);
    for (DWORD i = 0; EnumDisplayDevicesW(nullptr, i, &device, 0); ++i) {
        std::wcout << L"- " << device.DeviceString << L"\n";
        std::wcout << L"  name: " << device.DeviceName << L"\n";
        std::wcout << L"  id: " << device.DeviceID << L"\n";
        std::wcout << L"  stateFlags: 0x" << std::hex << device.StateFlags << std::dec << L"\n";
        device = {};
        device.cb = sizeof(device);
    }
    std::wcout << L"\n";
}

} // namespace

int wmain() {
    std::wcout << L"# GPUC Inspector\n\n";
    std::wcout << L"Mode: read-only user-mode inspection. No MMIO reads or writes are attempted.\n\n";
    std::wcout << L"Note: Configuration Manager may not expose allocated resources for null-driver ACPI devices.\n";
    std::wcout << L"If APP000B resources are absent here, compare with the PowerShell/WMI safe report.\n\n";

    PrintDisplayDevices();

    HDEVINFO info = SetupDiGetClassDevsW(nullptr, nullptr, nullptr, DIGCF_ALLCLASSES | DIGCF_PRESENT);
    if (info == INVALID_HANDLE_VALUE) {
        std::wcerr << L"SetupDiGetClassDevsW failed: " << FormatError(GetLastError()) << L"\n";
        return 1;
    }

    std::wcout << L"# Matching PnP Devices\n";
    for (DWORD index = 0;; ++index) {
        SP_DEVINFO_DATA data{};
        data.cbSize = sizeof(data);
        if (!SetupDiEnumDeviceInfo(info, index, &data)) {
            if (GetLastError() == ERROR_NO_MORE_ITEMS) {
                break;
            }
            continue;
        }

        const auto instanceId = GetInstanceId(info, data);
        const auto description = GetRegistryPropertyString(info, data, SPDRP_DEVICEDESC);
        const auto friendlyName = GetRegistryPropertyString(info, data, SPDRP_FRIENDLYNAME);
        const bool interesting =
            ContainsCaseInsensitive(instanceId, L"APP000B") ||
            ContainsCaseInsensitive(instanceId, L"VEN_1002") ||
            ContainsCaseInsensitive(instanceId, L"VEN_8086&DEV_3E9B") ||
            ContainsCaseInsensitive(description, L"graphics mux") ||
            ContainsCaseInsensitive(friendlyName, L"graphics mux") ||
            ContainsCaseInsensitive(description, L"Radeon Pro") ||
            ContainsCaseInsensitive(description, L"UHD Graphics");

        if (!interesting) {
            continue;
        }

        std::wcout << L"- InstanceId: " << instanceId << L"\n";
        if (!friendlyName.empty()) {
            std::wcout << L"  friendlyName: " << friendlyName << L"\n";
        }
        if (!description.empty()) {
            std::wcout << L"  description: " << description << L"\n";
        }

        const auto hardwareIds = GetRegistryPropertyString(info, data, SPDRP_HARDWAREID);
        const auto compatibleIds = GetRegistryPropertyString(info, data, SPDRP_COMPATIBLEIDS);
        const auto driverInf = GetDevicePropertyString(info, data, DEVPKEY_Device_DriverInfPath);
        const auto driverSection = GetDevicePropertyString(info, data, DEVPKEY_Device_DriverInfSection);
        const auto biosName = GetDevicePropertyString(info, data, DEVPKEY_Device_BiosDeviceName);
        const auto stack = GetDevicePropertyString(info, data, DEVPKEY_Device_Stack);

        if (!hardwareIds.empty()) std::wcout << L"  hardwareIds: " << hardwareIds << L"\n";
        if (!compatibleIds.empty()) std::wcout << L"  compatibleIds: " << compatibleIds << L"\n";
        if (!driverInf.empty()) std::wcout << L"  driverInf: " << driverInf << L"\n";
        if (!driverSection.empty()) std::wcout << L"  driverSection: " << driverSection << L"\n";
        if (!biosName.empty()) std::wcout << L"  biosName: " << biosName << L"\n";
        if (!stack.empty()) std::wcout << L"  stack: " << stack << L"\n";

        PrintAllocatedResources(data.DevInst);
    }

    SetupDiDestroyDeviceInfoList(info);
    return 0;
}
