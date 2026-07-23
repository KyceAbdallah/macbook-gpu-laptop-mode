#include <windows.h>
#include <cfgmgr32.h>
#include <comdef.h>
#include <initguid.h>
#include <devpkey.h>
#include <setupapi.h>
#include <wbemidl.h>

#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct ResourceInfo {
    std::wstring source;
    std::wstring type;
    unsigned long long start = 0;
    unsigned long long end = 0;
    std::wstring note;
};

struct DisplayInfo {
    std::wstring name;
    std::wstring deviceName;
    std::wstring deviceId;
    DWORD stateFlags = 0;
};

struct DeviceInfo {
    std::wstring instanceId;
    std::wstring friendlyName;
    std::wstring description;
    std::wstring hardwareIds;
    std::wstring compatibleIds;
    std::wstring driverInf;
    std::wstring driverSection;
    std::wstring biosName;
    std::wstring stack;
    std::wstring cmResourceStatus;
    std::vector<ResourceInfo> resources;
};

struct Report {
    std::vector<DisplayInfo> displays;
    std::vector<DeviceInfo> devices;
    std::vector<ResourceInfo> wmiGpucResources;
    std::wstring wmiStatus;
};

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
    stream.imbue(std::locale::classic());
    stream << L"0x" << std::uppercase << std::hex << std::setw(8) << std::setfill(L'0') << value;
    return stream.str();
}

std::wstring JsonEscape(const std::wstring& value) {
    std::wstringstream out;
    for (wchar_t ch : value) {
        switch (ch) {
        case L'\\': out << L"\\\\"; break;
        case L'"': out << L"\\\""; break;
        case L'\b': out << L"\\b"; break;
        case L'\f': out << L"\\f"; break;
        case L'\n': out << L"\\n"; break;
        case L'\r': out << L"\\r"; break;
        case L'\t': out << L"\\t"; break;
        default:
            if (ch < 0x20) {
                out << L"\\u" << std::hex << std::setw(4) << std::setfill(L'0') << static_cast<int>(ch);
            } else {
                out << ch;
            }
        }
    }
    return out.str();
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
            if (!joined.empty()) joined += L", ";
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
            if (!joined.empty()) joined += L", ";
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

std::optional<unsigned long long> ParseStartingAddress(const std::wstring& value) {
    const std::wstring marker = L"StartingAddress = ";
    const auto pos = value.find(marker);
    if (pos == std::wstring::npos) return std::nullopt;
    const auto start = pos + marker.size();
    auto end = value.find(L')', start);
    if (end == std::wstring::npos) end = value.size();
    try {
        return std::stoull(value.substr(start, end - start));
    } catch (...) {
        return std::nullopt;
    }
}

std::wstring EscapeWmiObjectPathString(const std::wstring& value) {
    std::wstring escaped;
    for (wchar_t ch : value) {
        if (ch == L'\\' || ch == L'"') {
            escaped += L'\\';
        }
        escaped += ch;
    }
    return escaped;
}

std::vector<ResourceInfo> GetAllocatedResources(DEVINST devInst, std::wstring& status) {
    std::vector<ResourceInfo> result;
    LOG_CONF logConf = 0;
    CONFIGRET cr = CM_Get_First_Log_Conf(&logConf, devInst, ALLOC_LOG_CONF);
    if (cr != CR_SUCCESS) {
        std::wstringstream s;
        s << L"none from CM_Get_First_Log_Conf ALLOC_LOG_CONF (CR=" << cr << L")";
        status = s.str();
        return result;
    }

    RES_DES resDes = 0;
    RESOURCEID resourceId = ResType_All;
    cr = CM_Get_Next_Res_Des(&resDes, logConf, ResType_All, &resourceId, 0);
    if (cr != CR_SUCCESS) {
        std::wstringstream s;
        s << L"none from CM_Get_Next_Res_Des (CR=" << cr << L")";
        status = s.str();
        CM_Free_Log_Conf_Handle(logConf);
        return result;
    }

    status = L"resources returned by Configuration Manager";
    while (cr == CR_SUCCESS) {
        ULONG size = 0;
        if (CM_Get_Res_Des_Data_Size(&size, resDes, 0) == CR_SUCCESS && size > 0) {
            std::vector<BYTE> data(size);
            if (CM_Get_Res_Des_Data(resDes, data.data(), size, 0) == CR_SUCCESS) {
                if (resourceId == ResType_Mem && size >= sizeof(MEM_RESOURCE)) {
                    auto* mem = reinterpret_cast<MEM_RESOURCE*>(data.data());
                    result.push_back(ResourceInfo{
                        L"ConfigurationManager",
                        L"memory",
                        mem->MEM_Header.MD_Alloc_Base,
                        mem->MEM_Header.MD_Alloc_End,
                        L"allocated memory resource"
                    });
                } else {
                    std::wstringstream note;
                    note << L"resource type " << resourceId << L": " << size << L" bytes";
                    result.push_back(ResourceInfo{L"ConfigurationManager", L"other", 0, 0, note.str()});
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
    return result;
}

Report CollectSetupApiReport() {
    Report report;

    DISPLAY_DEVICEW display{};
    display.cb = sizeof(display);
    for (DWORD i = 0; EnumDisplayDevicesW(nullptr, i, &display, 0); ++i) {
        report.displays.push_back(DisplayInfo{
            display.DeviceString,
            display.DeviceName,
            display.DeviceID,
            display.StateFlags
        });
        display = {};
        display.cb = sizeof(display);
    }

    HDEVINFO info = SetupDiGetClassDevsW(nullptr, nullptr, nullptr, DIGCF_ALLCLASSES | DIGCF_PRESENT);
    if (info == INVALID_HANDLE_VALUE) {
        DeviceInfo error;
        error.description = L"SetupDiGetClassDevsW failed: " + FormatError(GetLastError());
        report.devices.push_back(error);
        return report;
    }

    for (DWORD index = 0;; ++index) {
        SP_DEVINFO_DATA data{};
        data.cbSize = sizeof(data);
        if (!SetupDiEnumDeviceInfo(info, index, &data)) {
            if (GetLastError() == ERROR_NO_MORE_ITEMS) break;
            continue;
        }

        DeviceInfo device;
        device.instanceId = GetInstanceId(info, data);
        device.description = GetRegistryPropertyString(info, data, SPDRP_DEVICEDESC);
        device.friendlyName = GetRegistryPropertyString(info, data, SPDRP_FRIENDLYNAME);

        const bool interesting =
            ContainsCaseInsensitive(device.instanceId, L"APP000B") ||
            ContainsCaseInsensitive(device.instanceId, L"VEN_1002") ||
            ContainsCaseInsensitive(device.instanceId, L"VEN_8086&DEV_3E9B") ||
            ContainsCaseInsensitive(device.description, L"graphics mux") ||
            ContainsCaseInsensitive(device.friendlyName, L"graphics mux") ||
            ContainsCaseInsensitive(device.description, L"Radeon Pro") ||
            ContainsCaseInsensitive(device.description, L"UHD Graphics");

        if (!interesting) continue;

        device.hardwareIds = GetRegistryPropertyString(info, data, SPDRP_HARDWAREID);
        device.compatibleIds = GetRegistryPropertyString(info, data, SPDRP_COMPATIBLEIDS);
        device.driverInf = GetDevicePropertyString(info, data, DEVPKEY_Device_DriverInfPath);
        device.driverSection = GetDevicePropertyString(info, data, DEVPKEY_Device_DriverInfSection);
        device.biosName = GetDevicePropertyString(info, data, DEVPKEY_Device_BiosDeviceName);
        device.stack = GetDevicePropertyString(info, data, DEVPKEY_Device_Stack);
        device.resources = GetAllocatedResources(data.DevInst, device.cmResourceStatus);
        report.devices.push_back(device);
    }

    SetupDiDestroyDeviceInfoList(info);
    return report;
}

std::wstring VariantString(IWbemClassObject* object, const wchar_t* propertyName) {
    VARIANT value;
    VariantInit(&value);
    if (FAILED(object->Get(propertyName, 0, &value, nullptr, nullptr))) {
        VariantClear(&value);
        return L"";
    }
    std::wstring result;
    if (value.vt == VT_BSTR && value.bstrVal) {
        result = value.bstrVal;
    }
    VariantClear(&value);
    return result;
}

std::optional<unsigned long long> VariantUll(IWbemClassObject* object, const wchar_t* propertyName) {
    VARIANT value;
    VariantInit(&value);
    if (FAILED(object->Get(propertyName, 0, &value, nullptr, nullptr))) {
        VariantClear(&value);
        return std::nullopt;
    }

    std::optional<unsigned long long> result;
    if (value.vt == VT_BSTR && value.bstrVal) {
        try {
            result = std::stoull(value.bstrVal);
        } catch (...) {
            result = std::nullopt;
        }
    } else if (value.vt == VT_UI8) {
        result = value.ullVal;
    } else if (value.vt == VT_I8) {
        result = static_cast<unsigned long long>(value.llVal);
    } else if (value.vt == VT_UI4) {
        result = value.ulVal;
    } else if (value.vt == VT_I4) {
        result = static_cast<unsigned long long>(value.lVal);
    }
    VariantClear(&value);
    return result;
}

void AddWmiGpucResources(Report& report) {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool initialized = SUCCEEDED(hr);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        report.wmiStatus = L"CoInitializeEx failed";
        return;
    }

    hr = CoInitializeSecurity(nullptr, -1, nullptr, nullptr, RPC_C_AUTHN_LEVEL_DEFAULT,
                              RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE, nullptr);
    if (FAILED(hr) && hr != RPC_E_TOO_LATE) {
        report.wmiStatus = L"CoInitializeSecurity failed";
        if (initialized) CoUninitialize();
        return;
    }

    IWbemLocator* locator = nullptr;
    hr = CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER,
                          IID_IWbemLocator, reinterpret_cast<void**>(&locator));
    if (FAILED(hr)) {
        report.wmiStatus = L"CoCreateInstance IWbemLocator failed";
        if (initialized) CoUninitialize();
        return;
    }

    IWbemServices* services = nullptr;
    hr = locator->ConnectServer(_bstr_t(L"ROOT\\CIMV2"), nullptr, nullptr, nullptr, 0, nullptr, nullptr, &services);
    locator->Release();
    if (FAILED(hr)) {
        report.wmiStatus = L"WMI ConnectServer ROOT\\CIMV2 failed";
        if (initialized) CoUninitialize();
        return;
    }

    hr = CoSetProxyBlanket(services, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr,
                           RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE);
    if (FAILED(hr)) {
        report.wmiStatus = L"CoSetProxyBlanket failed";
        services->Release();
        if (initialized) CoUninitialize();
        return;
    }

    std::wstring gpucInstanceId;
    for (const auto& device : report.devices) {
        if (ContainsCaseInsensitive(device.instanceId, L"APP000B")) {
            gpucInstanceId = device.instanceId;
            break;
        }
    }

    if (gpucInstanceId.empty()) {
        report.wmiStatus = L"APP000B was not present in SetupAPI device list";
        services->Release();
        if (initialized) CoUninitialize();
        return;
    }

    std::wstringstream associatorsQuery;
    associatorsQuery << L"ASSOCIATORS OF {Win32_PnPEntity.DeviceID=\""
                     << EscapeWmiObjectPathString(gpucInstanceId)
                     << L"\"} WHERE ResultClass=Win32_DeviceMemoryAddress";

    IEnumWbemClassObject* enumerator = nullptr;
    hr = services->ExecQuery(
        _bstr_t(L"WQL"),
        _bstr_t(associatorsQuery.str().c_str()),
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
        nullptr,
        &enumerator);

    if (FAILED(hr)) {
        report.wmiStatus = L"WMI ASSOCIATORS query for APP000B memory resources failed";
        services->Release();
        if (initialized) CoUninitialize();
        return;
    }

    for (;;) {
        IWbemClassObject* object = nullptr;
        ULONG returned = 0;
        hr = enumerator->Next(WBEM_INFINITE, 1, &object, &returned);
        if (FAILED(hr) || returned == 0) break;

        auto memStart = VariantUll(object, L"StartingAddress");
        auto memEnd = VariantUll(object, L"EndingAddress");
        if (memStart && memEnd) {
            bool exists = false;
            for (const auto& existing : report.wmiGpucResources) {
                if (existing.start == *memStart && existing.end == *memEnd) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                report.wmiGpucResources.push_back(ResourceInfo{
                    L"WMI",
                    L"memory",
                    *memStart,
                    *memEnd,
                    L"ASSOCIATORS OF Win32_PnPEntity(APP000B) -> Win32_DeviceMemoryAddress"
                });
            }
        }
        object->Release();
    }
    enumerator->Release();

    if (report.wmiGpucResources.empty()) {
        report.wmiStatus = L"no APP000B memory resources returned by WMI";
    } else {
        report.wmiStatus = L"APP000B memory resources returned by WMI";
    }

    services->Release();
    if (initialized) CoUninitialize();
}

void WriteMarkdown(std::wostream& out, const Report& report) {
    out << L"# GPUC Inspector\n\n";
    out << L"Mode: read-only user-mode inspection. No MMIO reads or writes are attempted.\n\n";
    out << L"Note: Configuration Manager may not expose allocated resources for null-driver ACPI devices. This tool also attempts a read-only WMI resource fallback.\n\n";

    out << L"# Display Devices\n";
    for (const auto& display : report.displays) {
        out << L"- " << display.name << L"\n";
        out << L"  name: " << display.deviceName << L"\n";
        out << L"  id: " << display.deviceId << L"\n";
        out << L"  stateFlags: 0x" << std::hex << display.stateFlags << std::dec << L"\n";
    }
    out << L"\n";

    out << L"# Matching PnP Devices\n";
    for (const auto& device : report.devices) {
        out << L"- InstanceId: " << device.instanceId << L"\n";
        if (!device.friendlyName.empty()) out << L"  friendlyName: " << device.friendlyName << L"\n";
        if (!device.description.empty()) out << L"  description: " << device.description << L"\n";
        if (!device.hardwareIds.empty()) out << L"  hardwareIds: " << device.hardwareIds << L"\n";
        if (!device.compatibleIds.empty()) out << L"  compatibleIds: " << device.compatibleIds << L"\n";
        if (!device.driverInf.empty()) out << L"  driverInf: " << device.driverInf << L"\n";
        if (!device.driverSection.empty()) out << L"  driverSection: " << device.driverSection << L"\n";
        if (!device.biosName.empty()) out << L"  biosName: " << device.biosName << L"\n";
        if (!device.stack.empty()) out << L"  stack: " << device.stack << L"\n";
        if (!device.cmResourceStatus.empty()) out << L"  cmResources: " << device.cmResourceStatus << L"\n";
        for (const auto& resource : device.resources) {
            if (resource.type == L"memory") {
                out << L"  memory: " << HexUnsignedLongLong(resource.start) << L"-" << HexUnsignedLongLong(resource.end)
                    << L" (" << resource.source << L")\n";
            } else {
                out << L"  resource: " << resource.note << L" (" << resource.source << L")\n";
            }
        }
    }

    out << L"\n# WMI APP000B Resource Fallback\n";
    out << L"- Status: " << report.wmiStatus << L"\n";
    for (const auto& resource : report.wmiGpucResources) {
        out << L"- MemoryResource: " << HexUnsignedLongLong(resource.start) << L"-" << HexUnsignedLongLong(resource.end) << L"\n";
        out << L"  - Source: " << resource.note << L"\n";
    }
}

void WriteJson(std::wostream& out, const Report& report) {
    out << L"{\n";
    out << L"  \"mode\": \"read-only user-mode inspection\",\n";
    out << L"  \"displayDevices\": [\n";
    for (size_t i = 0; i < report.displays.size(); ++i) {
        const auto& d = report.displays[i];
        out << L"    {\"name\":\"" << JsonEscape(d.name) << L"\",\"deviceName\":\"" << JsonEscape(d.deviceName)
            << L"\",\"deviceId\":\"" << JsonEscape(d.deviceId) << L"\",\"stateFlags\":\"0x"
            << std::uppercase << std::hex << d.stateFlags << std::dec << L"\"}";
        out << (i + 1 == report.displays.size() ? L"\n" : L",\n");
    }
    out << L"  ],\n";
    out << L"  \"matchingPnpDevices\": [\n";
    for (size_t i = 0; i < report.devices.size(); ++i) {
        const auto& d = report.devices[i];
        out << L"    {\n";
        out << L"      \"instanceId\": \"" << JsonEscape(d.instanceId) << L"\",\n";
        out << L"      \"friendlyName\": \"" << JsonEscape(d.friendlyName) << L"\",\n";
        out << L"      \"description\": \"" << JsonEscape(d.description) << L"\",\n";
        out << L"      \"hardwareIds\": \"" << JsonEscape(d.hardwareIds) << L"\",\n";
        out << L"      \"compatibleIds\": \"" << JsonEscape(d.compatibleIds) << L"\",\n";
        out << L"      \"driverInf\": \"" << JsonEscape(d.driverInf) << L"\",\n";
        out << L"      \"driverSection\": \"" << JsonEscape(d.driverSection) << L"\",\n";
        out << L"      \"biosName\": \"" << JsonEscape(d.biosName) << L"\",\n";
        out << L"      \"stack\": \"" << JsonEscape(d.stack) << L"\",\n";
        out << L"      \"cmResourceStatus\": \"" << JsonEscape(d.cmResourceStatus) << L"\",\n";
        out << L"      \"resources\": [";
        for (size_t r = 0; r < d.resources.size(); ++r) {
            const auto& resource = d.resources[r];
            out << (r == 0 ? L"" : L",") << L"{\"source\":\"" << JsonEscape(resource.source)
                << L"\",\"type\":\"" << JsonEscape(resource.type) << L"\",\"start\":\""
                << HexUnsignedLongLong(resource.start) << L"\",\"end\":\"" << HexUnsignedLongLong(resource.end)
                << L"\",\"note\":\"" << JsonEscape(resource.note) << L"\"}";
        }
        out << L"]\n";
        out << L"    }" << (i + 1 == report.devices.size() ? L"\n" : L",\n");
    }
    out << L"  ],\n";
    out << L"  \"wmiGpucResourceFallback\": {\n";
    out << L"    \"status\": \"" << JsonEscape(report.wmiStatus) << L"\",\n";
    out << L"    \"resources\": [";
    for (size_t i = 0; i < report.wmiGpucResources.size(); ++i) {
        const auto& r = report.wmiGpucResources[i];
        out << (i == 0 ? L"" : L",") << L"{\"type\":\"memory\",\"start\":\"" << HexUnsignedLongLong(r.start)
            << L"\",\"end\":\"" << HexUnsignedLongLong(r.end) << L"\",\"note\":\"" << JsonEscape(r.note) << L"\"}";
    }
    out << L"]\n";
    out << L"  }\n";
    out << L"}\n";
}

void WriteWideFile(const std::filesystem::path& path, void (*writer)(std::wostream&, const Report&), const Report& report) {
    std::wofstream file(path, std::ios::binary);
    file.imbue(std::locale::classic());
    writer(file, report);
}

std::optional<std::filesystem::path> ParseOutputDir(int argc, wchar_t** argv) {
    for (int i = 1; i < argc; ++i) {
        const std::wstring arg = argv[i];
        if ((arg == L"--output-dir" || arg == L"-o") && i + 1 < argc) {
            return std::filesystem::path(argv[i + 1]);
        }
    }
    return std::nullopt;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    Report report = CollectSetupApiReport();
    AddWmiGpucResources(report);

    WriteMarkdown(std::wcout, report);

    if (auto outputDir = ParseOutputDir(argc, argv)) {
        std::filesystem::create_directories(*outputDir);
        const auto markdownPath = *outputDir / L"gpuc-inspector.md";
        const auto jsonPath = *outputDir / L"gpuc-inspector.json";
        WriteWideFile(markdownPath, WriteMarkdown, report);
        WriteWideFile(jsonPath, WriteJson, report);
        std::wcout << L"\n# Output Files\n";
        std::wcout << L"- " << markdownPath.wstring() << L"\n";
        std::wcout << L"- " << jsonPath.wstring() << L"\n";
    }

    return 0;
}
