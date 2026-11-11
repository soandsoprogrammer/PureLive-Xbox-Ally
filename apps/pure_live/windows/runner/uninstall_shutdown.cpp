#include "uninstall_shutdown.h"

#include <tlhelp32.h>
#include <string>
#include <vector>

namespace {
struct Target {
  DWORD pid;
  HANDLE process;
};

std::wstring CanonicalPath(const wchar_t* path) {
  HANDLE file = ::CreateFileW(path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, 0, nullptr);
  if (file == INVALID_HANDLE_VALUE) return {};
  wchar_t buffer[32768] = {};
  const DWORD count = ::GetFinalPathNameByHandleW(file, buffer, 32768, 0);
  ::CloseHandle(file);
  return count > 0 && count < 32768 ? std::wstring(buffer) : std::wstring();
}

BOOL CALLBACK AskWindowToExit(HWND window, LPARAM parameter) {
  const auto& targets = *reinterpret_cast<const std::vector<Target>*>(parameter);
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  for (const auto& target : targets) {
    if (pid == target.pid) {
      // This bypasses hide-to-tray, but lets Dart finish recordings and save
      // geometry before destroying the window. Never broadcast to other apps.
      ::PostMessageW(window, UninstallShutdownMessage(), 0, 0);
      break;
    }
  }
  return TRUE;
}
}  // namespace

UINT UninstallShutdownMessage() {
  static const UINT message =
      ::RegisterWindowMessageW(L"PureLive.UninstallShutdown.v1");
  return message;
}

int ShutdownInstalledInstances() {
  wchar_t own_path[32768] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, own_path, 32768);
  if (length == 0 || length >= 32768 || UninstallShutdownMessage() == 0) return 1;
  const std::wstring installed_path = CanonicalPath(own_path);
  if (installed_path.empty()) return 1;
  HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return 1;
  std::vector<Target> targets;
  bool inaccessible = false;
  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  if (::Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID == ::GetCurrentProcessId() ||
          _wcsicmp(entry.szExeFile, L"pure_live.exe") != 0) continue;
      HANDLE process = ::OpenProcess(
          PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE,
          entry.th32ProcessID);
      if (!process) {
        // A still-existing but unreadable same-name process cannot safely be
        // classified. Abort before uninstalling instead of killing by name.
        if (::GetLastError() != ERROR_INVALID_PARAMETER) inaccessible = true;
        continue;
      }
      wchar_t path[32768] = {};
      DWORD size = 32768;
      if (!::QueryFullProcessImageNameW(process, 0, path, &size)) {
        if (::WaitForSingleObject(process, 0) != WAIT_OBJECT_0) inaccessible = true;
        ::CloseHandle(process);
        continue;
      }
      const std::wstring image_path = CanonicalPath(path);
      if (image_path.empty()) {
        inaccessible = true;
        ::CloseHandle(process);
      } else if (_wcsicmp(image_path.c_str(), installed_path.c_str()) == 0) {
        targets.push_back({entry.th32ProcessID, process});
      } else {
        ::CloseHandle(process);
      }
    } while (::Process32NextW(snapshot, &entry));
  } else {
    inaccessible = true;
  }
  ::CloseHandle(snapshot);
  if (!inaccessible) {
    const ULONGLONG deadline = ::GetTickCount64() + 15000;
    bool running;
    do {
      running = false;
      // An instance may still be starting and attach its window later.
      ::EnumWindows(AskWindowToExit, reinterpret_cast<LPARAM>(&targets));
      for (const auto& target : targets) {
        if (::WaitForSingleObject(target.process, 0) != WAIT_OBJECT_0) running = true;
      }
      if (!running) break;
      ::Sleep(100);
    } while (::GetTickCount64() < deadline);
    inaccessible = running;
  }
  for (const auto& target : targets) ::CloseHandle(target.process);
  // A legacy runner ignores this command and returns normal exit code 0.
  // The distinct acknowledgement prevents an old binary after downgrade
  // from falsely allowing the newer uninstall script to delete locked files.
  return inaccessible ? 1 : 42;
}
