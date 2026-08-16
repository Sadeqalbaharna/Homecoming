#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>
#include <filesystem>
#include <fstream>

#include "flutter_window.h"
#include "utils.h"

namespace {
std::wstring CurrentExecutablePath();

void RegisterKaiAutoStart() {
  wchar_t executable[MAX_PATH]{};
  if (GetModuleFileNameW(nullptr, executable, MAX_PATH) == 0) return;
  const std::wstring command = L"\"" + std::wstring(executable) +
                               L"\" --coordinator-worker --background";
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_SET_VALUE, &key) != ERROR_SUCCESS) {
    return;
  }
  RegSetValueExW(key, L"Kai Homecoming", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(command.c_str()),
                 static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
}

void RegisterHomecomingProtocol() {
  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) return;
  const std::wstring base = L"Software\\Classes\\homecoming";
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, base.c_str(), 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  const std::wstring label = L"URL:Homecoming Protocol";
  const std::wstring empty;
  RegSetValueExW(key, nullptr, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(label.c_str()),
                 static_cast<DWORD>((label.size() + 1) * sizeof(wchar_t)));
  RegSetValueExW(key, L"URL Protocol", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(empty.c_str()),
                 static_cast<DWORD>(sizeof(wchar_t)));
  RegCloseKey(key);

  const std::wstring command_key = base + L"\\shell\\open\\command";
  if (RegCreateKeyExW(HKEY_CURRENT_USER, command_key.c_str(), 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  const std::wstring command = L"\"" + executable +
                               L"\" --whoop-oauth \"%1\"";
  RegSetValueExW(key, nullptr, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(command.c_str()),
                 static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
}

bool CaptureWhoopOAuthCallback(const std::vector<std::string>& arguments) {
  const auto marker = std::find(arguments.begin(), arguments.end(),
                                "--whoop-oauth");
  if (marker == arguments.end() || std::next(marker) == arguments.end()) {
    return false;
  }
  const std::string callback = *std::next(marker);
  if (callback.rfind("homecoming://whoop/oauth?", 0) != 0) return true;

  wchar_t local_app_data[MAX_PATH]{};
  const DWORD length = GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data, static_cast<DWORD>(MAX_PATH));
  if (length == 0 || length >= MAX_PATH) return true;
  const std::filesystem::path directory =
      std::filesystem::path(local_app_data) / L"Homecoming";
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  if (error) return true;
  std::ofstream output(directory / L"whoop_oauth_callback.txt",
                       std::ios::binary | std::ios::trunc);
  output << callback;
  return true;
}

std::wstring CurrentExecutablePath() {
  wchar_t executable[MAX_PATH]{};
  if (GetModuleFileNameW(nullptr, executable, MAX_PATH) == 0) return L"";
  return executable;
}

void StartKaiWatchdog() {
  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) return;

  std::wstring command = L"\"" + executable + L"\" --watchdog --watch-pid=" +
                         std::to_wstring(GetCurrentProcessId());
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr,
                     FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup,
                     &process)) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
}

DWORD ParseWatchedProcessId(const std::vector<std::string>& arguments) {
  const std::string prefix = "--watch-pid=";
  for (const auto& argument : arguments) {
    if (argument.rfind(prefix, 0) != 0) continue;
    try {
      return static_cast<DWORD>(std::stoul(argument.substr(prefix.size())));
    } catch (...) {
      return 0;
    }
  }
  return 0;
}

int WatchKaiAndRecover(DWORD process_id) {
  if (process_id == 0) return EXIT_FAILURE;
  HANDLE watched = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
                               FALSE, process_id);
  if (watched == nullptr) return EXIT_FAILURE;

  WaitForSingleObject(watched, INFINITE);
  DWORD exit_code = EXIT_FAILURE;
  GetExitCodeProcess(watched, &exit_code);
  CloseHandle(watched);

  // A deliberate tray quit returns zero. Crashes, forced termination, and
  // other abnormal exits bring the coordinator back without user intervention.
  if (exit_code == EXIT_SUCCESS) return EXIT_SUCCESS;

  Sleep(1500);
  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) return EXIT_FAILURE;
  std::wstring command = L"\"" + executable +
                         L"\" --coordinator-worker --background --recovered";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr,
                      FALSE, 0, nullptr, nullptr, &startup, &process)) {
    return EXIT_FAILURE;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return EXIT_SUCCESS;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (CaptureWhoopOAuthCallback(command_line_arguments)) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }
  RegisterHomecomingProtocol();
  const bool is_watchdog =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--watchdog") != command_line_arguments.end();
  if (is_watchdog) {
    const int result = WatchKaiAndRecover(
        ParseWatchedProcessId(command_line_arguments));
    ::CoUninitialize();
    return result;
  }
  const bool start_hidden =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--background") != command_line_arguments.end();
  const bool coordinator_worker =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--coordinator-worker") != command_line_arguments.end();

  HANDLE coordinator_mutex = nullptr;
  HANDLE desktop_room_mutex = nullptr;
  if (coordinator_worker) {
    coordinator_mutex =
        CreateMutexW(nullptr, FALSE, L"Local\\KaiHomecomingCentralCoordinator");
    if (coordinator_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
      CloseHandle(coordinator_mutex);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
    RegisterKaiAutoStart();
    StartKaiWatchdog();
  } else {
    desktop_room_mutex =
        CreateMutexW(nullptr, FALSE, L"Local\\KaiHomecomingDesktopRoom");
    if (desktop_room_mutex != nullptr &&
        GetLastError() == ERROR_ALREADY_EXISTS) {
      CloseHandle(desktop_room_mutex);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, start_hidden || coordinator_worker,
                       coordinator_worker);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Kai", origin, size)) {
    if (desktop_room_mutex != nullptr) CloseHandle(desktop_room_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (coordinator_mutex != nullptr) CloseHandle(coordinator_mutex);
  if (desktop_room_mutex != nullptr) CloseHandle(desktop_room_mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
