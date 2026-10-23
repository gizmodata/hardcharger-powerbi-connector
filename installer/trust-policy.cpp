// Read Power BI's complete REG_MULTI_SZ policy. MSI string conditions cannot
// reliably search an AppSearch property containing embedded NUL separators.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <msi.h>
#include <msiquery.h>
#include <cwchar>
#include <vector>

extern "C" __declspec(dllexport) UINT __stdcall DetectTrustedCertificate(MSIHANDLE session) {
    wchar_t thumbprint[41] = {};
    DWORD length = 41;
    if (MsiGetPropertyW(session, L"HARDCHARGERSIGNER", thumbprint, &length) != ERROR_SUCCESS || length != 40) {
        return ERROR_INSTALL_FAILURE;
    }
    constexpr auto key = L"SOFTWARE\\Policies\\Microsoft\\Power BI Desktop";
    constexpr auto name = L"TrustedCertificateThumbprints";
    constexpr DWORD flags = RRF_RT_REG_MULTI_SZ | RRF_SUBKEY_WOW6464KEY;
    DWORD bytes = 0;
    LSTATUS status = RegGetValueW(HKEY_LOCAL_MACHINE, key, name, flags, nullptr, nullptr, &bytes);
    bool found = false;
    if (status != ERROR_FILE_NOT_FOUND && status != ERROR_PATH_NOT_FOUND) {
        if (status != ERROR_SUCCESS || bytes > 1024 * 1024) return ERROR_INSTALL_FAILURE;
        std::vector<wchar_t> values(bytes / sizeof(wchar_t) + 2, L'\0');
        status = RegGetValueW(HKEY_LOCAL_MACHINE, key, name, flags, nullptr, values.data(), &bytes);
        if (status != ERROR_SUCCESS) return ERROR_INSTALL_FAILURE;
        for (const wchar_t* entry = values.data(); *entry; entry += std::wcslen(entry) + 1) {
            if (_wcsicmp(entry, thumbprint) == 0) { found = true; break; }
        }
    }
    return MsiSetPropertyW(session, L"PREEXISTINGTRUSTEDCERTIFICATE", found ? L"1" : L"");
}
