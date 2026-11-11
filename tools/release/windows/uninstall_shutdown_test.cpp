// Native harness: link the production shutdown helper without Flutter.
// Run only in generated directories; each directory must contain its own copy
// named pure_live.exe. A same-name copy elsewhere must remain running.
#include <windows.h>
#include <string>
#include "uninstall_shutdown.h"

namespace {
bool stubborn = false;
void Marker(const wchar_t* name) {
  wchar_t module[32768] = {};
  GetModuleFileNameW(nullptr, module, 32768);
  std::wstring path(module);
  path = path.substr(0, path.find_last_of(L"\\/")) + L"\\" + name;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                           nullptr, CREATE_ALWAYS, 0, nullptr);
  if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
}
LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  if (message == UninstallShutdownMessage()) {
    if (stubborn) return 0;
    Marker(L"stopped.txt");
    DestroyWindow(window);
    return 0;
  }
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR args, int) {
  const std::wstring arguments(args);
  if (arguments == L"--shutdown-for-uninstall") return ShutdownInstalledInstances();
  stubborn = arguments == L"--stubborn";
  WNDCLASSW type = {};
  type.lpfnWndProc = WindowProc;
  type.hInstance = instance;
  type.lpszClassName = L"PureLiveUninstallShutdownTest";
  if (!RegisterClassW(&type)) return 2;
  if (!CreateWindowW(type.lpszClassName, L"PureLive generated uninstall test",
                     WS_OVERLAPPEDWINDOW, 0, 0, 300, 200,
                     nullptr, nullptr, instance, nullptr)) return 3;
  Marker(L"ready.txt");
  MSG message;
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  return 0;
}
