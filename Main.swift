import SwiftUI
import AppKit
import UserNotifications

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { Self.model?.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.title == "AustinHelpU" }) { window.makeKeyAndOrderFront(nil) }
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let part = response.notification.request.content.userInfo["part"] as? String else { return }
        await MainActor.run {
            if let product = Self.model?.products.first(where: { $0.part == part }) { Self.model?.openProduct(product) }
        }
    }
}
@main struct XiaozhangApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    @StateObject var model = AppModel()
    var body: some Scene {
        WindowGroup("AustinHelpU", id: "main") {
            ContentView().environmentObject(model).onAppear { ApplicationDelegate.model = model }
        }.defaultSize(width: 1260, height: 850).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("添加监控…") { model.showAdd = true }.keyboardShortcut("n") }
            CommandGroup(after: .appInfo) {
                Button("显示监控台") { model.page = "监控台"; NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.title == "AustinHelpU" })?.makeKeyAndOrderFront(nil) }
            }
        }
        MenuBarExtra {
            TrayView().environmentObject(model)
        } label: { Label(model.running ? "AustinHelpU · 蹲守中" : "AustinHelpU", systemImage: model.running ? "dot.radiowaves.left.and.right" : "binoculars") }
    }
}
struct TrayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text("AustinHelpU · \(model.running ? "正在蹲守" : "已暂停")")
        Text("\(model.preferences.monitors.count) 组监控 · \(model.inStockCount) 组有货")
        Divider()
        Button("打开监控台") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.running ? "暂停监控" : "开始蹲守") { model.running ? model.stop() : model.start() }
        Divider()
        Button("退出 AustinHelpU") { model.shutdown(); NSApp.terminate(nil) }
    }
}
