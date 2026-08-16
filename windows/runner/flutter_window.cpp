#include "flutter_window.h"

#include <optional>
#include <cmath>
#include <cstdint>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include <firebase_auth/firebase_auth_plugin_c_api.h>
#include <firebase_core/firebase_core_plugin_c_api.h>
#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <pasteboard/pasteboard_plugin.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>
#include "resource.h"

namespace {
constexpr UINT_PTR kKaiHeartbeatTimer = 0x4B4149;
constexpr UINT kKaiHeartbeatTickMs = 140;
constexpr int kHeartIconSize = 24;
constexpr UINT kKaiTrayMessage = WM_APP + 0x4B;
constexpr UINT kKaiGracefulQuitMessage = WM_APP + 0x4C;
constexpr UINT kTrayOpen = 0x4B01;
constexpr UINT kTrayQuit = 0x4B02;
const UINT kTaskbarButtonCreated =
    RegisterWindowMessageW(L"TaskbarButtonCreated");

// The headless coordinator never plays audio. Avoid instantiating the Windows
// audio plugin in that process: its engine-teardown destructor can fault after
// Dart has already completed a durable graceful drain. Desktop rooms retain the
// generated full plugin set, including audio.
void RegisterCoordinatorPlugins(flutter::PluginRegistry* registry) {
  FirebaseAuthPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FirebaseAuthPluginCApi"));
  FirebaseCorePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FirebaseCorePluginCApi"));
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
  PasteboardPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PasteboardPlugin"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden,
                             bool coordinator_worker)
    : project_(project),
      start_hidden_(start_hidden),
      coordinator_worker_(coordinator_worker) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  if (coordinator_worker_) {
    RegisterCoordinatorPlugins(flutter_controller_->engine());
  } else {
    RegisterPlugins(flutter_controller_->engine());
  }
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  if (coordinator_worker_) AddTrayIcon();

  taskbar_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "kai.homecoming/taskbar",
          &flutter::StandardMethodCodec::GetInstance());
  taskbar_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setHeartbeatState") {
          result->NotImplemented();
          return;
        }
        const auto* state =
            std::get_if<std::string>(call.arguments());
        if (state == nullptr) {
          result->Error("invalid_state", "Heartbeat state must be a string");
          return;
        }
        SetTaskbarHeartbeatState(*state);
        result->Success();
      });

  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "kai.homecoming/lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
  lifecycle_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "quitCoordinator") {
          result->NotImplemented();
          return;
        }
        if (!coordinator_worker_ || quitting_) {
          result->Error("quit_refused",
                        "Only the active coordinator can exit normally");
          return;
        }
        // Complete the Dart method call before the window is destroyed. The
        // local HTTP seam has already replied and flushed its durable writers.
        result->Success();
        PostMessageW(GetHandle(), kKaiGracefulQuitMessage, 0, 0);
      });

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  ReleaseTaskbarHeartbeat();
  taskbar_channel_.reset();
  lifecycle_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Explorer may publish the taskbar button just after Dart reports the first
  // healthy beat. Repaint at the authoritative Windows lifecycle event so a
  // cold launch never has to wait for the next 30-second Core heartbeat.
  if (message == kTaskbarButtonCreated) {
    PaintTaskbarHeartbeat();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kKaiGracefulQuitMessage:
      if (coordinator_worker_ && !quitting_) {
        QuitFromTray();
      }
      return 0;
    case WM_CLOSE:
      if (coordinator_worker_ && !quitting_) {
        // Closing the visible room must not kill the coordinator living behind
        // it. Hide the window; the tray heart remains the explicit way back in
        // and its menu retains a real, deliberate full-quit action.
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case kKaiTrayMessage:
      // NOTIFYICON_VERSION_4 packs the notification into LOWORD(lParam) and
      // the icon id into HIWORD(lParam); comparing the full LPARAM makes tray
      // clicks silently fail as soon as the modern notification contract is on.
      if (LOWORD(lparam) == WM_LBUTTONUP ||
          LOWORD(lparam) == WM_LBUTTONDBLCLK ||
          LOWORD(lparam) == NIN_SELECT) {
        RestoreFromTray();
        return 0;
      }
      if (LOWORD(lparam) == WM_RBUTTONUP ||
          LOWORD(lparam) == WM_CONTEXTMENU) {
        POINT cursor{};
        GetCursorPos(&cursor);
        HMENU menu = CreatePopupMenu();
        AppendMenuW(menu, MF_STRING, kTrayOpen, L"Open Kai");
        AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        AppendMenuW(menu, MF_STRING, kTrayQuit, L"Quit Kai completely");
        SetForegroundWindow(hwnd);
        const UINT selected = TrackPopupMenu(
            menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, cursor.x,
            cursor.y, 0, hwnd, nullptr);
        DestroyMenu(menu);
        if (selected == kTrayOpen) RestoreFromTray();
        if (selected == kTrayQuit) QuitFromTray();
        PostMessage(hwnd, WM_NULL, 0, 0);
        return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kKaiHeartbeatTimer) {
        taskbar_beat_tick_ = (taskbar_beat_tick_ + 1) % 10;
        PaintTaskbarHeartbeat();
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetTaskbarHeartbeatState(const std::string& state) {
  if (state != "connecting" && state != "healthy" &&
      state != "reconnecting" && state != "offline") {
    return;
  }
  if (taskbar_heartbeat_state_ == state && taskbar_heart_small_ != nullptr) {
    return;
  }

  taskbar_heartbeat_state_ = state;
  taskbar_beat_tick_ = 0;
  if (taskbar_ == nullptr) {
    if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar_)))) {
      taskbar_ = nullptr;
    } else if (FAILED(taskbar_->HrInit())) {
      taskbar_->Release();
      taskbar_ = nullptr;
    }
  }

  if (taskbar_heart_small_) DestroyIcon(taskbar_heart_small_);
  if (taskbar_heart_large_) DestroyIcon(taskbar_heart_large_);

  COLORREF color = RGB(255, 91, 110);
  if (state == "healthy") color = RGB(53, 230, 211);
  if (state == "connecting" || state == "reconnecting") {
    color = RGB(255, 183, 77);
  }
  taskbar_heart_small_ = CreateHeartIcon(color, 0.78);
  taskbar_heart_large_ = CreateHeartIcon(color, 1.0);

  if (state == "healthy") {
    SetTimer(GetHandle(), kKaiHeartbeatTimer, kKaiHeartbeatTickMs, nullptr);
  } else {
    KillTimer(GetHandle(), kKaiHeartbeatTimer);
  }
  PaintTaskbarHeartbeat();
}

void FlutterWindow::PaintTaskbarHeartbeat() {
  const bool strong_beat = taskbar_heartbeat_state_ == "healthy" &&
                           (taskbar_beat_tick_ == 0 ||
                            taskbar_beat_tick_ == 3);
  HICON icon = strong_beat ? taskbar_heart_large_ : taskbar_heart_small_;
  const wchar_t* description = L"Kai Core offline";
  if (taskbar_heartbeat_state_ == "healthy") {
    description = L"Kai Core alive";
  } else if (taskbar_heartbeat_state_ == "connecting") {
    description = L"Kai Core connecting";
  } else if (taskbar_heartbeat_state_ == "reconnecting") {
    description = L"Kai Core reconnecting";
  }
  if (taskbar_ != nullptr) {
    taskbar_->SetOverlayIcon(GetHandle(), icon, description);
  }
  PaintTrayHeartbeat(icon);
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_) return;
  tray_icon_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kKaiTrayMessage;
  tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                              MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"Kai Core connecting");
  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
  if (tray_icon_added_) {
    tray_icon_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) return;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_icon_added_ = false;
}

void FlutterWindow::RestoreFromTray() {
  if (coordinator_worker_) {
    LaunchDesktopRoom();
    return;
  }
  start_hidden_ = false;
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::LaunchDesktopRoom() {
  wchar_t executable[MAX_PATH]{};
  if (GetModuleFileNameW(nullptr, executable, MAX_PATH) == 0) return;
  std::wstring command = L"\"" + std::wstring(executable) + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE, 0,
                     nullptr, nullptr, &startup, &process)) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
}

void FlutterWindow::QuitFromTray() {
  quitting_ = true;
  RemoveTrayIcon();
  DestroyWindow(GetHandle());
}

void FlutterWindow::PaintTrayHeartbeat(HICON icon) {
  if (!tray_icon_added_ || icon == nullptr) return;
  tray_icon_.uFlags = NIF_ICON | NIF_TIP;
  tray_icon_.hIcon = icon;
  const wchar_t* tooltip = L"Kai Core offline";
  if (taskbar_heartbeat_state_ == "healthy") tooltip = L"Kai Core alive";
  if (taskbar_heartbeat_state_ == "connecting") {
    tooltip = L"Kai Core connecting";
  }
  if (taskbar_heartbeat_state_ == "reconnecting") {
    tooltip = L"Kai Core reconnecting";
  }
  wcscpy_s(tray_icon_.szTip, tooltip);
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_);
}

HICON FlutterWindow::CreateHeartIcon(COLORREF color, double scale) {
  BITMAPV5HEADER header{};
  header.bV5Size = sizeof(BITMAPV5HEADER);
  header.bV5Width = kHeartIconSize;
  header.bV5Height = -kHeartIconSize;
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00FF0000;
  header.bV5GreenMask = 0x0000FF00;
  header.bV5BlueMask = 0x000000FF;
  header.bV5AlphaMask = 0xFF000000;

  void* bits = nullptr;
  HDC screen = GetDC(nullptr);
  HBITMAP color_bitmap = CreateDIBSection(
      screen, reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS, &bits,
      nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (color_bitmap == nullptr || bits == nullptr) return nullptr;

  auto* pixels = static_cast<std::uint32_t*>(bits);
  const std::uint32_t argb = 0xFF000000u |
      (static_cast<std::uint32_t>(GetRValue(color)) << 16) |
      (static_cast<std::uint32_t>(GetGValue(color)) << 8) |
      static_cast<std::uint32_t>(GetBValue(color));
  for (int py = 0; py < kHeartIconSize; ++py) {
    for (int px = 0; px < kHeartIconSize; ++px) {
      const double x = ((px + 0.5) - kHeartIconSize / 2.0) /
                       (kHeartIconSize * 0.29 * scale);
      const double y = -((py + 0.5) - kHeartIconSize / 2.0) /
                       (kHeartIconSize * 0.29 * scale) + 0.18;
      const double a = x * x + y * y - 1.0;
      const bool inside = a * a * a - x * x * y * y * y <= 0.0;
      pixels[py * kHeartIconSize + px] = inside ? argb : 0;
    }
  }

  HBITMAP mask_bitmap =
      CreateBitmap(kHeartIconSize, kHeartIconSize, 1, 1, nullptr);
  ICONINFO icon_info{};
  icon_info.fIcon = TRUE;
  icon_info.hbmColor = color_bitmap;
  icon_info.hbmMask = mask_bitmap;
  HICON icon = CreateIconIndirect(&icon_info);
  DeleteObject(mask_bitmap);
  DeleteObject(color_bitmap);
  return icon;
}

void FlutterWindow::ReleaseTaskbarHeartbeat() {
  KillTimer(GetHandle(), kKaiHeartbeatTimer);
  if (taskbar_) {
    taskbar_->SetOverlayIcon(GetHandle(), nullptr, L"");
    taskbar_->Release();
    taskbar_ = nullptr;
  }
  if (taskbar_heart_small_) {
    DestroyIcon(taskbar_heart_small_);
    taskbar_heart_small_ = nullptr;
  }
  if (taskbar_heart_large_) {
    DestroyIcon(taskbar_heart_large_);
    taskbar_heart_large_ = nullptr;
  }
}
