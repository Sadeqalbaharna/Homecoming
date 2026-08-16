#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shobjidl.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false,
                         bool coordinator_worker = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetTaskbarHeartbeatState(const std::string& state);
  void PaintTaskbarHeartbeat();
  HICON CreateHeartIcon(COLORREF color, double scale);
  void ReleaseTaskbarHeartbeat();
  void AddTrayIcon();
  void RemoveTrayIcon();
  void RestoreFromTray();
  void QuitFromTray();
  void PaintTrayHeartbeat(HICON icon);
  void LaunchDesktopRoom();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      taskbar_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lifecycle_channel_;
  ITaskbarList3* taskbar_ = nullptr;
  HICON taskbar_heart_small_ = nullptr;
  HICON taskbar_heart_large_ = nullptr;
  std::string taskbar_heartbeat_state_ = "connecting";
  unsigned int taskbar_beat_tick_ = 0;
  bool start_hidden_ = false;
  bool coordinator_worker_ = false;
  bool quitting_ = false;
  bool tray_icon_added_ = false;
  NOTIFYICONDATAW tray_icon_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
