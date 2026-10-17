import SwiftUI
import AppKit

typealias LocalState<Value> = SwiftUI.State<Value>

let jade = Color(red: 0.10, green: 0.39, blue: 0.32)
let ink = Color(red: 0.12, green: 0.18, blue: 0.16)
let paper = Color(red: 0.96, green: 0.96, blue: 0.93)
let muted = Color(red: 0.47, green: 0.51, blue: 0.48)

struct Panel<Content: View>: View {
    var title: String; var subtitle: String = ""; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 15, weight: .semibold)); if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(muted) } } }
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(0.07)))
    }
}
struct BrandIcon: View {
    var size: CGFloat = 48
    var body: some View {
        Group { if let url = Bundle.main.url(forResource: "brand", withExtension: "png"), let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFill() } else { Image(systemName: "dot.radiowaves.left.and.right").resizable().scaledToFit().padding(10).foregroundStyle(jade).background(Color.orange.opacity(0.15)) } }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.24))
    }
}
struct CredentialPrivacyNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("凭证与隐私说明", systemImage: "lock.shield").font(.system(size: 12, weight: .semibold)).foregroundStyle(jade)
            Text("订阅地址与 Bark 凭证保存在本机 macOS 钥匙串，读取时可能出现系统授权提示。更新应用后也可能需要重新授权。")
                .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("查看保存内容、授权与联网用途") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("保存什么：你填写的代理订阅地址、Bark 服务器地址及设备 Key，用于下次启动继续使用，不随安装包分发。监控清单和普通设置保存在本机配置文件。")
                    Text("为什么弹窗：cn.xiaozhang.watch 是本应用保存凭证的标识。本应用仅按自己的标识读取已保存的凭证，不查询其他应用的密码。")
                    Text("如何选择：确认正在使用本应用后，可在 macOS 系统弹窗中输入 Mac 登录密码并选择“允许”。不要在软件的订阅输入框里填写登录密码。选择“不允许”会导致相关订阅加载或 Bark 推送无法使用。")
                    Text("联网用途：加载订阅会访问你填写的订阅服务；启用 Bark 后，商品、门店和提醒内容会发送至你配置的推送服务器。库存请求通过所选网络或代理访问 Apple。凭证不会上传给本软件开发者。")
                    Text("代理组件：为运行代理，节点连接凭证还会写入本机仅当前用户可读写的代理配置文件，并非所有凭证都只保存在钥匙串中。")
                }.font(.system(size: 10)).foregroundStyle(muted).lineSpacing(4).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11))
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(jade.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                Group {
                    switch model.page {
                    case "代理线路": ProxyView()
                    case "提醒设置": ReminderView()
                    case "活动日志": ActivityView()
                    default: DashboardView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(paper)
        }.foregroundStyle(ink).frame(minWidth: 1120, minHeight: 730).preferredColorScheme(.light)
        .sheet(isPresented: $model.showAdd) { AddMonitorView().environmentObject(model) }
        .alert("AustinHelpU 提醒", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 11) { BrandIcon(size: 42); VStack(alignment: .leading, spacing: 4) { Text("小张帮你蹲").font(.system(size: 16, weight: .bold)); Text("AustinHelpU").font(.system(size: 10)).foregroundStyle(muted) } }.padding(.top, 24)
            VStack(spacing: 7) {
                nav("监控台", "dot.radiowaves.left.and.right")
                nav("代理线路", "network")
                nav("提醒设置", "bell.badge")
                nav("活动日志", "text.alignleft")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: "cup.and.saucer").font(.system(size: 23)).foregroundStyle(jade)
                Text("你忙你的，Austin 来蹲。").font(.system(size: 12, weight: .semibold))
                Text("关掉窗口后，仍可在菜单栏找到 AustinHelpU。电脑需保持联网运行。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(5)
            }.padding(16).background(jade.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            HStack { Text("macOS · 预览版 0.1.6").font(.system(size: 10)).foregroundStyle(muted); Spacer(); Circle().fill(jade).frame(width: 5,height: 5) }.padding(.bottom, 20)
        }.padding(.horizontal, 18).frame(width: 218).background(.white)
    }
    func nav(_ title: String, _ symbol: String) -> some View {
        Button { model.page = title } label: { HStack(spacing: 12) { Image(systemName: symbol).frame(width: 18); Text(title).font(.system(size: 13, weight: model.page == title ? .semibold : .regular)); Spacer(); if model.page == title { Circle().fill(jade).frame(width: 5,height: 5) } }.padding(.horizontal, 13).padding(.vertical, 13).foregroundStyle(model.page == title ? jade : muted).background(model.page == title ? jade.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
    }
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) { Text(model.page).font(.system(size: 23, weight: .bold)); Text(subtitle).font(.system(size: 11)).foregroundStyle(muted) }
            Spacer()
            HStack(spacing: 6) { Circle().fill(model.demo ? Color.orange : model.running ? jade : muted).frame(width: 6,height: 6); Text(model.demo ? "界面演示" : model.querying ? "正在查询" : model.running ? "蹲守中" : "准备就绪").font(.system(size: 11, weight: .medium)) }.padding(.horizontal, 12).padding(.vertical, 8).background(.white, in: Capsule())
            Button { model.running ? model.stop() : model.start() } label: { Label(model.running ? "暂停监控" : "开始蹲守", systemImage: model.running ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 11).foregroundStyle(.white).background(jade, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).disabled(model.busyProxy || model.demo)
        }.padding(.horizontal, 28).padding(.vertical, 23)
    }
    var subtitle: String {
        switch model.page { case "代理线路": return "只为库存查询选择线路，让长时间蹲守更从容。"; case "提醒设置": return "蹲到的第一时间，让消息找到你。"; case "活动日志": return "每次查询、线路切换和到货提醒，都有记录。"; default: return "Apple 直营店取货监控 · 中国大陆" }
    }
}
struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                HStack(spacing: 14) {
                    metric("监控组合", value: "\(model.demo ? 4 : model.preferences.monitors.count)", symbol: "iphone")
                    metric("关注城市", value: "\(model.demo ? 1 : model.cityCount)", symbol: "mappin.and.ellipse")
                    metric("当前有货", value: "\(model.demo ? 1 : model.inStockCount)", symbol: "checkmark.circle", green: true)
                }
                HStack(alignment: .top, spacing: 20) {
                    monitorPanel
                    VStack(spacing: 16) { querySettings; routeSummary }.frame(width: 253)
                }
                HStack { Image(systemName: "info.circle"); Text("库存状态以 Apple 下单页面为准；查询失败会显示“未确认”。"); Spacer(); Button(model.demo ? "退出界面演示" : "看看演示效果") { model.toggleDemo() }.disabled(model.running) }.font(.system(size: 10)).foregroundStyle(muted)
            }.padding(28)
        }
    }
    var hero: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("LET’S WAIT FOR SOMETHING GOOD").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.white.opacity(0.55))
                Text(model.demo ? "这次，演示一下怎么蹲。" : model.running ? "Austin 正在认真蹲守。" : "想要的那一款，Austin 帮你等。").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                Text(model.demo ? "此处展示模拟库存，不会查询或发送提醒。" : "选好 iPhone 和门店，到货后第一时间提醒你。").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                if model.running { TimelineView(.periodic(from: .now, by: 1)) { context in Text(model.querying ? "正在核对门店取货信息…" : "下一轮查询 · \(max(0, Int(model.nextCheck?.timeIntervalSince(context.date) ?? 0))) 秒").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.85)) } }
            }
            Spacer(minLength: 5)
            BrandIcon(size: 120).rotationEffect(.degrees(-5)).shadow(color: .black.opacity(0.12), radius: 15,y: 6)
        }.padding(26).frame(maxWidth: .infinity, minHeight: 177, alignment: .leading).background(LinearGradient(colors: [jade, Color(red: 0.15, green: 0.47, blue: 0.38)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20))
    }
    func metric(_ title: String, value: String, symbol: String, green: Bool = false) -> some View {
        HStack { VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 11)).foregroundStyle(muted); Text(value).font(.system(size: 28,weight: .semibold,design: .rounded)).foregroundStyle(green ? jade : ink) }; Spacer(); Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(green ? jade : muted.opacity(0.6)).padding(10).background((green ? jade : muted).opacity(0.07), in: RoundedRectangle(cornerRadius: 12)) }.padding(19).frame(maxWidth: .infinity).background(.white,in: RoundedRectangle(cornerRadius: 16))
    }
    var monitorPanel: some View {
        Panel(title: "") {
            HStack { Text("我的蹲守清单").font(.system(size: 15, weight: .semibold)); if model.demo { Text("演示数据").font(.system(size: 9,weight: .medium)).padding(5).background(Color.orange.opacity(0.15),in: Capsule()) }; Spacer(); Button { model.showAdd = true } label: { Label("添加监控",systemImage: "plus").font(.system(size: 11,weight: .medium)) }.buttonStyle(.bordered).tint(jade).disabled(model.running || model.demo) }
            if model.displayedMonitors.isEmpty {
                VStack(spacing: 14) { Image(systemName: "binoculars").font(.system(size: 34)).foregroundStyle(jade.opacity(0.65)); Text("还没告诉 Austin，你想蹲哪一款？").font(.system(size: 13,weight: .medium)); Text("选择颜色、容量和直营店，就可以开始了。").font(.system(size: 11)).foregroundStyle(muted); Button("添加第一组监控") { model.showAdd = true }.buttonStyle(.borderedProminent).tint(jade) }.frame(maxWidth: .infinity,minHeight: 245)
            } else {
                HStack { Text("商品 / 门店"); Spacer(); Text("取货状态").frame(width: 112); Text("操作").frame(width: 32) }.font(.system(size: 10)).foregroundStyle(muted).padding(.vertical, 7)
                ForEach(model.displayedMonitors) { monitor in
                    MonitorRow(monitor: monitor, demo: model.demo).environmentObject(model)
                    Divider().opacity(0.5)
                }
            }
        }
    }
    var querySettings: some View {
        Panel(title: "蹲守节奏", subtitle: "每轮结束后，再等待指定间隔") {
            HStack { Text("查询间隔").font(.system(size: 12)); Spacer(); Text("\(model.preferences.interval) 秒").font(.system(size: 12,weight: .semibold,design: .monospaced)).foregroundStyle(jade) }
            Slider(value: Binding(get: { Double(model.preferences.interval) }, set: { model.preferences.interval = Int($0); model.persist() }), in: 15...180, step: 15).tint(jade)
            HStack { Text("15 秒"); Spacer(); Text("180 秒") }.font(.system(size: 9)).foregroundStyle(muted)
            Divider()
            Toggle("有货后暂停", isOn: $model.preferences.pauseOnHit).font(.system(size: 11)).toggleStyle(.switch).controlSize(.small)
            Toggle("监控时防止自动睡眠", isOn: $model.preferences.preventSleep).font(.system(size: 11)).toggleStyle(.switch).controlSize(.small)
            Text("建议从 30 秒开始；遇到网站拒绝时会延长等待。合盖或手动睡眠仍会停止查询。").font(.system(size: 10)).foregroundStyle(muted).lineSpacing(4)
        }.disabled(model.running).onChange(of: model.preferences.pauseOnHit) { model.persist() }.onChange(of: model.preferences.preventSleep) { model.persist() }
    }
    var routeSummary: some View {
        Panel(title: "当前查询线路") {
            HStack(spacing: 9) { Image(systemName: "network").foregroundStyle(jade); Text(model.preferences.proxy ? model.currentNode : "跟随系统网络").font(.system(size: 12,weight: .medium)).lineLimit(2) }
            Text(model.preferences.proxy ? "\(model.nodes.count) 个节点 · \(model.preferences.timedRotation ? "定时 + 异常切换" : "异常时智能切换")" : "可添加代理订阅，管理查询使用的节点。").font(.system(size: 10)).foregroundStyle(muted).lineSpacing(4)
            Button("管理代理线路 →") { model.page = "代理线路" }.buttonStyle(.plain).font(.system(size: 11,weight: .semibold)).foregroundStyle(jade)
        }
    }
}
struct MonitorRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @LocalState private var refreshed = false
    let monitor: Monitor; var demo: Bool
    var refreshColor: Color { monitor.status == "未确认" ? .orange : jade }
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "iphone").font(.system(size: 23)).foregroundStyle(jade.opacity(0.8)).frame(width: 30)
            VStack(alignment: .leading,spacing: 6) {
                Button { model.openProduct(monitor.product) } label: { Text(monitor.product.name).font(.system(size: 11,weight: .semibold)).multilineTextAlignment(.leading) }.buttonStyle(.plain)
                Text("\(monitor.store.city) · \(monitor.store.name)").font(.system(size: 10)).foregroundStyle(muted)
                HStack(spacing: 4) {
                    Image(systemName: monitor.status == "未确认" ? "exclamationmark.circle" : "arrow.clockwise")
                        .rotationEffect(.degrees(refreshed && !reduceMotion ? 360 : 0))
                    Text(refreshed ? (monitor.status == "未确认" ? "查询异常 · 结果未确认" : "刚刚刷新") : (monitor.checked.map { "检查于 " + $0.formatted(date: .omitted,time: .standard) } ?? "尚未查询"))
                }.font(.system(size: 9)).foregroundStyle(refreshed ? refreshColor : muted.opacity(0.8))
            }.frame(maxWidth: .infinity,alignment: .leading)
            VStack(spacing: 5) { Text(monitor.status).font(.system(size: 10,weight: .semibold)).foregroundStyle(monitor.status == "有货" ? jade : muted).padding(.horizontal,10).padding(.vertical,6).background((monitor.status == "有货" ? jade : muted).opacity(0.08),in: Capsule()); Text(monitor.detail).font(.system(size: 9)).foregroundStyle(muted).lineLimit(2).multilineTextAlignment(.center) }.frame(width:112).help(monitor.detail)
            Button { model.remove(monitor.id) } label: { Image(systemName: "trash").font(.system(size:11)).foregroundStyle(muted) }.buttonStyle(.plain).disabled(model.running || demo).frame(width:32)
        }.padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(refreshColor.opacity(refreshed ? 0.10 : 0)))
        .task(id: monitor.checked) {
            refreshed = false
            guard !demo, let checked = monitor.checked, abs(checked.timeIntervalSinceNow) < 3 else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { refreshed = true }
            do { try await Task.sleep(nanoseconds: 1_400_000_000) } catch { refreshed = false; return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { refreshed = false }
        }
    }
}
struct AddMonitorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @LocalState var city = "北京"; @LocalState var family = ""; @LocalState var search = ""
    @LocalState var selectedProducts = Set<String>(); @LocalState var selectedStores = Set<String>()
    var families: [String] { Array(Set(model.products.map(\.family))).sorted { $0.localizedStandardCompare($1) == .orderedDescending } }
    var body: some View {
        VStack(alignment: .leading,spacing:20) {
            HStack { VStack(alignment:.leading,spacing:7) { Text("告诉 Austin，你想蹲什么？").font(.system(size:23,weight:.bold)); Text("多选型号和门店，Austin 会自动组合并跳过重复项。").font(.system(size:12)).foregroundStyle(muted) }; Spacer(); Button { dismiss() } label: { Image(systemName:"xmark") }.buttonStyle(.plain) }
            HStack(alignment:.top,spacing:22) {
                VStack(alignment:.leading,spacing:12) {
                    Text("01  选择 iPhone").font(.system(size:13,weight:.semibold))
                    Picker("机型",selection:$family) { ForEach(families,id:\.self) { Text($0).tag($0) } }.labelsHidden()
                    TextField("搜索颜色、容量或零件号",text:$search).textFieldStyle(.roundedBorder)
                    ScrollView { VStack(alignment:.leading,spacing:11) { ForEach(model.products.filter { $0.family == family && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.part.localizedCaseInsensitiveContains(search)) }) { p in Toggle(isOn: Binding(get:{ selectedProducts.contains(p.id) },set:{ if $0 { selectedProducts.insert(p.id) } else { selectedProducts.remove(p.id) } })) { VStack(alignment:.leading,spacing:4) { Text("\(p.capacity) · \(p.color)").font(.system(size:12)); Text(p.part).font(.system(size:9,design:.monospaced)).foregroundStyle(muted) } }.toggleStyle(.checkbox) } }.padding(8) }.background(paper,in:RoundedRectangle(cornerRadius:12))
                }.frame(maxWidth:.infinity)
                VStack(alignment:.leading,spacing:12) {
                    Text("02  选择直营店").font(.system(size:13,weight:.semibold))
                    Picker("城市",selection:$city) { ForEach(Array(Set(model.stores.map(\.city))).sorted(),id:\.self) { Text($0).tag($0) } }.labelsHidden()
                    HStack { Text("可跨城市保留勾选").font(.system(size:10)).foregroundStyle(muted); Spacer(); Button("本城全选") { selectedStores.formUnion(model.stores.filter { $0.city == city }.map(\.id)) }.font(.system(size:10)) }
                    ScrollView { VStack(alignment:.leading,spacing:15) { ForEach(model.stores.filter { $0.city == city }) { s in Toggle(isOn:Binding(get:{ selectedStores.contains(s.id) },set:{ if $0 { selectedStores.insert(s.id) } else { selectedStores.remove(s.id) } })) { VStack(alignment:.leading,spacing:4) { Text(s.name).font(.system(size:12)); Text(s.address).font(.system(size:10)).foregroundStyle(muted) } }.toggleStyle(.checkbox) } }.padding(8) }.background(paper,in:RoundedRectangle(cornerRadius:12))
                }.frame(maxWidth:.infinity)
            }
            HStack { Text("已选 \(selectedProducts.count) 个配置 × \(selectedStores.count) 家门店").font(.system(size:12)).foregroundStyle(muted); Spacer(); Button("取消") { dismiss() }; Button("添加 \(selectedProducts.count * selectedStores.count) 组监控") { model.add(products:selectedProducts,stores:selectedStores); dismiss() }.buttonStyle(.borderedProminent).tint(jade).disabled(selectedProducts.isEmpty || selectedStores.isEmpty) }
        }.padding(30).frame(width:790,height:560).foregroundStyle(ink).onAppear { family = families.first(where: { $0.contains("18 Pro Max") }) ?? families.first ?? "" }.tint(jade)
    }
}
struct ProxyView: View {
    @EnvironmentObject var model: AppModel
    @LocalState var subscriptionName = ""; @LocalState var subscriptionURL = ""
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack(alignment:.top,spacing:20) {
                    VStack(spacing:20) { enginePanel; subscriptionPanel }.frame(maxWidth:.infinity)
                    strategyPanel.frame(width:280)
                }
                nodesPanel
                Text("切换节点不保证改变出口 IP 或解除网站限制。软件仍会控制查询频率，并在连续失败时等待。").font(.system(size:10)).foregroundStyle(muted)
            }.padding(28)
        }.tint(jade)
    }
    var enginePanel: some View {
        Panel(title:"专用代理组件",subtitle:"独立运行，只承载Austin 的库存查询") {
            HStack { Label(model.proxy.isInstalled ? "组件已就绪" : "首次使用需安装组件",systemImage:model.proxy.isInstalled ? "checkmark.seal" : "shippingbox").font(.system(size:12,weight:.medium)); Spacer(); if model.busyProxy { ProgressView().controlSize(.small) } }
            Text(model.proxyMessage).font(.system(size:11)).foregroundStyle(muted).textSelection(.enabled)
            HStack { Button(model.proxy.isInstalled ? "更新官方组件" : "下载官方组件") { model.installCore() }; Button("手动导入…") { model.importCore() } }.disabled(model.running || model.busyProxy)
            Text("下载来源：MetaCubeX/mihomo 官方 GitHub Release；安装前校验 SHA-256。").font(.system(size:9)).foregroundStyle(muted)
        }
    }
    var subscriptionPanel: some View {
        Panel(title:"代理订阅",subtitle:"首版支持标准 Clash / mihomo YAML 订阅") {
            CredentialPrivacyNotice()
            ForEach(model.preferences.subscriptions) { sub in
                HStack { Image(systemName:"link").foregroundStyle(jade); VStack(alignment:.leading,spacing:4) { Text(sub.name).font(.system(size:12,weight:.medium)); Text("订阅凭证保存在 macOS 钥匙串").font(.system(size:9)).foregroundStyle(muted) }; Spacer(); Toggle("启用",isOn:Binding(get:{ model.preferences.subscriptions.first(where:{$0.id == sub.id})?.enabled ?? false },set:{ v in if let i = model.preferences.subscriptions.firstIndex(where:{$0.id == sub.id}) { model.preferences.subscriptions[i].enabled = v; model.persist() } })).labelsHidden().toggleStyle(.switch).controlSize(.small); Button { model.deleteSubscription(sub.id) } label:{ Image(systemName:"trash") }.buttonStyle(.plain) }.disabled(model.running || model.busyProxy)
            }
            TextField("订阅名称，例如：我的常用线路",text:$subscriptionName).textFieldStyle(.roundedBorder)
            SecureField("粘贴 HTTPS 订阅地址",text:$subscriptionURL).textFieldStyle(.roundedBorder)
            HStack { Button("添加订阅") { if model.addSubscription(name:subscriptionName,url:subscriptionURL) { subscriptionName = ""; subscriptionURL = "" } }.disabled(subscriptionURL.isEmpty); Spacer(); Button("加载 / 更新节点") { model.refreshProxy() }.buttonStyle(.borderedProminent).disabled(model.preferences.subscriptions.isEmpty) }.disabled(model.running || model.busyProxy)
            Text("多个订阅需使用不同节点名称；不兼容或重名会明确报错。").font(.system(size:10)).foregroundStyle(muted)
        }
    }
    var strategyPanel: some View {
        Panel(title:"线路策略") {
            Toggle("使用专用代理",isOn:$model.preferences.proxy).toggleStyle(.switch).font(.system(size:12))
            Divider()
            Label("异常时智能切换",systemImage:"arrow.triangle.2.circlepath").font(.system(size:12,weight:.medium))
            Text("当前节点正常时保持使用；网站拒绝后让该节点冷却，再选择其他节点。").font(.system(size:11)).foregroundStyle(muted).lineSpacing(4)
            Toggle("同时开启定时轮换",isOn:$model.preferences.timedRotation).toggleStyle(.switch).font(.system(size:11))
            if model.preferences.timedRotation { Stepper("每 \(model.preferences.rotateMinutes) 分钟",value:$model.preferences.rotateMinutes,in:1...60).font(.system(size:11)) }
            Divider()
            TextField("节点关键词筛选，可留空",text:$model.preferences.nodeFilter).textFieldStyle(.roundedBorder)
            Text("冷却逐级延长：5 / 10 / 20 / 30 分钟。连不通的节点暂时跳过 60 秒。").font(.system(size:10)).foregroundStyle(muted).lineSpacing(4)
            Text("当前：\(model.currentNode.isEmpty ? "尚未选择" : model.currentNode)").font(.system(size:11,weight:.semibold)).foregroundStyle(jade)
        }.disabled(model.running || model.busyProxy).onChange(of:model.preferences.proxy) { model.persist() }.onChange(of:model.preferences.timedRotation) { model.persist() }.onChange(of:model.preferences.rotateMinutes) { model.persist() }.onChange(of:model.preferences.nodeFilter) { model.persist() }
    }
    var nodesPanel: some View {
        Panel(title:"节点池",subtitle:"取消勾选的节点不会参与监控轮换；加载节点不会开始库存查询") {
            if model.nodes.isEmpty { HStack { Spacer(); Text("添加订阅并加载后，节点会出现在这里。").font(.system(size:12)).foregroundStyle(muted); Spacer() }.padding(.vertical,26) }
            ForEach(model.nodes.filter { model.preferences.nodeFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(model.preferences.nodeFilter) }) { node in
                HStack {
                    Toggle("",isOn:Binding(get:{ !model.preferences.excludedNodes.contains(node.name) },set:{ enabled in if enabled { model.preferences.excludedNodes.removeAll { $0 == node.name } } else { model.preferences.excludedNodes.append(node.name) }; model.persist() })).labelsHidden().toggleStyle(.checkbox).disabled(model.running)
                    Text(node.name).font(.system(size:12)).lineLimit(1)
                    if model.currentNode == node.name { Text("当前").font(.system(size:9,weight:.medium)).foregroundStyle(jade).padding(5).background(jade.opacity(0.08),in:Capsule()) }
                    Spacer()
                    if let delay = node.delay { Text(delay > 0 ? "\(delay) ms" : "超时").font(.system(size:11,design:.monospaced)).foregroundStyle(delay > 0 ? jade : .orange) }
                    TimelineView(.periodic(from:.now,by:1)) { context in Text(node.coolingUntil.map { $0 > context.date ? "冷却 \(Int($0.timeIntervalSince(context.date)))s" : "可用" } ?? "待检测").font(.system(size:10)).foregroundStyle(muted).frame(width:85,alignment:.trailing) }
                }.padding(.vertical,4)
            }
        }
    }
}
struct ReminderView: View {
    @EnvironmentObject var model: AppModel
    @LocalState var bark = ""; @LocalState var saved = false
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            CredentialPrivacyNotice()
            Panel(title:"到货提醒",subtitle:"默认仅在确认有货且状态发生变化时提醒") {
                Toggle("播放 Mac 提示音",isOn:$model.preferences.sound)
                Toggle("发送 macOS 系统通知",isOn:$model.preferences.notification)
                Toggle("推送到 iPhone（Bark）",isOn:$model.preferences.bark)
                if model.preferences.bark { SecureField("https://api.day.app/你的设备Key",text:$bark).textFieldStyle(.roundedBorder); HStack { Button("保存 Bark 地址") { saved = Vault.set("bark",bark.trimmingCharacters(in:.whitespacesAndNewlines)); if !saved { model.error = "Bark 地址未能保存到钥匙串" } }; if saved { Text("已保存到钥匙串").font(.system(size:10)).foregroundStyle(jade) } }; Text("使用自建服务器也需 HTTPS；地址包含设备 Key。").font(.system(size:10)).foregroundStyle(muted) }
                Divider()
                Toggle("持续有货时，每 5 分钟再次提醒",isOn:$model.preferences.repeatAlert)
                Button("测试已开启的提醒方式") { model.testAlert() }.buttonStyle(.borderedProminent).tint(jade)
                Text("测试消息不代表有货。通知需要系统授权，手机推送需在 iPhone 上安装并配置 Bark。").font(.system(size:11)).foregroundStyle(muted)
            }
            Panel(title:"运行说明") {
                Label("关闭窗口，监控继续在菜单栏运行",systemImage:"menubar.rectangle")
                Label("彻底退出应用或电脑休眠后，查询会停止",systemImage:"moon")
                Label("下次启动恢复监控清单，需手动开始蹲守",systemImage:"arrow.clockwise")
                Text("这是一款独立的库存提醒工具，与 Apple 无关联。库存可能随时变化；首版不包含自动加购、辅助结账或下单。").font(.system(size:11)).foregroundStyle(muted).lineSpacing(5)
            }.font(.system(size:12))
        }.padding(28).frame(maxWidth:760,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading) }.tint(jade).onAppear { bark = Vault.get("bark") }
        .onChange(of:model.preferences.sound) { model.persist() }.onChange(of:model.preferences.notification) { model.persist() }.onChange(of:model.preferences.bark) { model.persist() }.onChange(of:model.preferences.repeatAlert) { model.persist() }
    }
}
struct ActivityView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("最近 \(model.logs.count) 条记录").font(.system(size:12)).foregroundStyle(muted); Spacer(); Button("导出日志…") { model.exportLogs() }; Button("清空") { model.logs.removeAll() } }
            ScrollView { LazyVStack(alignment:.leading,spacing:0) { ForEach(model.logs) { entry in HStack(alignment:.top,spacing:16) { Text(entry.date.formatted(date:.omitted,time:.standard)).font(.system(size:10,design:.monospaced)).foregroundStyle(muted).frame(width:67,alignment:.leading); Circle().fill(entry.warning ? Color.orange : jade).frame(width:5,height:5).padding(.top,5); Text(entry.text).font(.system(size:12)).lineSpacing(5).textSelection(.enabled); Spacer() }.padding(15); Divider().opacity(0.4) } }.frame(maxWidth:.infinity,alignment:.leading) }.background(.white,in:RoundedRectangle(cornerRadius:16))
        }.padding(28)
    }
}
