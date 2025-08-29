//
//  ContentView.swift
//  RouterHost
//
//  Created by LiuBo on 2025/8/29.
//

import SwiftUI

// 1. 定义应用中所有页面的ID（实现PageIdentifier协议）
enum AppPage: PageIdentifier {
    case home
    case userProfile(id: String)  // 带参数的用户详情页
    case settings
    case about
    case login
    case webView(url: URL)        // 带URL参数的网页视图
    case alertDemo
    case formModal
    case nestedModal
    case shareSheet
    
    // 实现描述信息，用于调试日志
    var description: String {
        switch self {
        case .home:
            return "首页"
        case .userProfile(let id):
            return "用户详情(id:\(id))"
        case .settings:
            return "设置"
        case .about:
            return "关于我们"
        case .login:
            return "登录页"
        case .webView(let url):
            return "网页视图(\(url.absoluteString))"
        case .alertDemo:
            return "alert页"
        case .formModal:
            return "表单页"
        case .nestedModal:
            return "嵌套页"
        case .shareSheet:
            return "分享sheet页"
        }
    }
}

// 2. 实现登录状态管理（用于演示拦截器功能）
class AuthManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    var userName: String? = nil
    
    func login(user: String, password: String) -> Bool {
        // 模拟登录验证
        if user == "admin" && password == "123456" {
            isLoggedIn = true
            userName = user
            return true
        }
        return false
    }
    
    func logout() {
        isLoggedIn = false
        userName = nil
    }
}

// 3. 实现路由拦截器（需要登录的页面进行拦截）
class LoginInterceptor: RouterInterceptor {
    weak var authManager: AuthManager?
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }
    
    // 拦截需要登录的页面
    func shouldPush(to id: any PageIdentifier) -> Bool {
        guard let appPage = id as? AppPage else { return true }
        
        // 需要登录的页面列表
        let needAuthPages: [AppPage] = [.userProfile(id: ""), .settings, .about]
        
        // 检查当前页面是否需要登录
        if needAuthPages.contains(where: { $0.isSameType(as: appPage) }) {
            guard let isLoggedIn = authManager?.isLoggedIn else { return false }
            if !isLoggedIn {
                // 未登录，跳转到登录页
                // 修复：使用MainActor.run确保在主actor上下文中执行
                Task { @MainActor in
                    if let router = Router.shared {
                        router.push(id: AppPage.login) {
                            LoginView()
                        }
                    }
                }
                return false
            }
        }
        return true
    }
    
    func shouldPop(to id: any PageIdentifier) -> Bool {
        return true // 不拦截返回操作
    }
}


// 为AppPage添加类型检查辅助方法
extension AppPage {
    // 检查是否为同一类型（忽略关联值）
    func isSameType(as other: AppPage) -> Bool {
        switch (self, other) {
        case (.home, .home): return true
        case (.userProfile, .userProfile): return true
        case (.settings, .settings): return true
        case (.about, .about): return true
        case (.login, .login): return true
        case (.webView, .webView): return true
        default: return false
        }
    }
}

// 4. 实现各个页面视图

// 首页
struct HomeView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("首页")
                    .font(.largeTitle)
                    .padding()
                
                if let userName = authManager.userName {
                    Text("当前登录：\(userName)")
                        .foregroundColor(.green)
                    
                    Button("退出登录") {
                        authManager.logout()
                    }
                    .foregroundColor(.red)
                }
                
                // 基础跳转示例
                Button("前往用户详情页") {
                    router.push(id: AppPage.userProfile(id: "1001")) {
                        UserProfileView(userId: "1001")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                
                // 跳转到设置页
                Button("前往设置页") {
                    router.push(id: AppPage.settings) {
                        SettingsView()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                
                // 模态弹窗示例
                Button("模态展示关于页面") {
                    router.present(id: AppPage.about) {
                        AboutView()
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("模态窗口演示") {
                    router.push(id: AppPage.home) { // 先push到演示页面
                        ModalDemoView()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("首页")
    }
}

// 用户详情页
struct UserProfileView: View {
    @EnvironmentObject var router: Router
    let userId: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("用户详情")
                .font(.title)
            
            Text("用户ID: \(userId)")
                .foregroundColor(.secondary)
            
            Button("返回上一页") {
                router.pop()
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Button("返回首页") {
                router.popToRoot()
            }
            .buttonStyle(SecondaryButtonStyle())
            
            Button("跳转到网页视图") {
                if let url = URL(string: "https://developer.apple.com") {
                    router.push(id: AppPage.webView(url: url)) {
                        WebView(url: url)
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            
            // 替换当前页面示例
            Button("替换当前页面为网页视图") {
                if let url = URL(string: "https://www.apple.com") {
                    router.replaceTop(id: AppPage.webView(url: url)) {
                        WebView(url: url)
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding()
    }
}

// 设置页
struct SettingsView: View {
    @EnvironmentObject var router: Router
    
    var body: some View {
        List {
            Button("前往关于页面") {
                router.push(id: AppPage.about) {
                    AboutView()
                }
            }
            
            Button("替换根页面（测试）") {
                router.replaceRoot(id: AppPage.home) {
                    HomeView()
                }
            }
            .foregroundColor(.red)
            
            Button("修改导航栏样式") {
                router.navigationBarConfig = Router.NavigationBarConfig(
                    tintColor: .white,
                    barTintColor: .purple,
                    titleColor: .white,
                    largeTitleMode: .always
                )
            }
        }
        .navigationTitle("设置")
    }
}

// 关于页面
struct AboutView: View {
    @EnvironmentObject var router: Router
    
    var body: some View {
        VStack(spacing: 20) {
            Text("关于我们")
                .font(.title)
            
            Text("这是一个演示Router功能的示例应用")
                .multilineTextAlignment(.center)
                .padding()
            
            Button("关闭（模态）") {
                router.dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Button("跳转到设置页") {
                router.dismiss() // 先关闭模态
                router.push(id: AppPage.settings) {
                    SettingsView()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding()
    }
}

// 登录页面
struct LoginView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var authManager: AuthManager
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("请登录")
                .font(.title)
            
            TextField("用户名", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            SecureField("密码", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button("登录") {
                if authManager.login(user: username, password: password) {
                    router.pop() // 登录成功返回上一页
                } else {
                    errorMessage = "用户名或密码错误（测试用：admin/123456）"
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Button("取消") {
                router.pop()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding()
        .navigationTitle("登录")
    }
}

// 网页视图
struct WebView: View {
    @EnvironmentObject var router: Router
    let url: URL
    @State private var isLoading = true
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("加载中...")
            }
            
            UIKitWebView(url: url, isLoading: $isLoading)
                .edgesIgnoringSafeArea(.bottom)
        }
        .navigationTitle(Text(url.host ?? "网页浏览"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("关闭") {
                    router.pop()
                }
            }
        }
    }
}

// UIKit WebView包装
struct UIKitWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    
    func makeUIView(context: Context) -> UIWebView {
        let webView = UIWebView()
        webView.delegate = context.coordinator
        webView.loadRequest(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ uiView: UIWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIWebViewDelegate {
        let parent: UIKitWebView
        
        init(_ parent: UIKitWebView) {
            self.parent = parent
        }
        
        func webViewDidStartLoad(_ webView: UIWebView) {
            parent.isLoading = true
        }
        
        func webViewDidFinishLoad(_ webView: UIWebView) {
            parent.isLoading = false
        }
        
        func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
            parent.isLoading = false
        }
    }
}

// 演示模态弹窗基础用法
struct ModalDemoView: View {
    @EnvironmentObject var router: Router
    
    var body: some View {
        List {
            // 基础模态弹窗
            Button("展示简单信息弹窗 overFullScreen") {
                router.present(id: AppPage.alertDemo, animated: true, modalPresentationStyle: .overFullScreen) {
                    AlertDemoView()
                }
            }
            
            // 基础模态弹窗
            Button("展示简单信息弹窗 fullScreen") {
                router.present(id: AppPage.alertDemo, animated: true, modalPresentationStyle: .fullScreen) {
                    AlertDemoView()
                }
            }
            
            // 基础模态弹窗
            Button("展示简单信息弹窗 popover") {
                router.present(id: AppPage.alertDemo, animated: true, modalPresentationStyle: .popover) {
                    AlertDemoView()
                }
            }
            
            // 基础模态弹窗
            Button("展示简单信息弹窗 formSheet") {
                router.present(id: AppPage.alertDemo, animated: true, modalPresentationStyle: .formSheet) {
                    AlertDemoView()
                }
            }
            
            // 基础模态弹窗
            Button("展示简单信息弹窗 pageSheet") {
                router.present(id: AppPage.alertDemo, animated: true, modalPresentationStyle: .pageSheet) {
                    AlertDemoView()
                }
            }

            // 带导航栏的表单弹窗
            Button("显示表单弹窗") {
                router.present(id: AppPage.formModal) {
                    NavigationView {
                        FormModalView()
                            .navigationTitle("用户表单")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("取消") {
                                        router.dismiss()
                                    }
                                }
                            }
                    }
                }
            }
            
            // 嵌套模态弹窗
            Button("显示嵌套弹窗") {
                router.present(id: AppPage.nestedModal) {
                    NestedModalView()
                }
            }
            
            // 带动画的模态切换
            Button("自定义动画弹窗") {
                router.present(id: AppPage.shareSheet,animated: true, modalPresentationStyle: .custom) {
                    ShareSheetView()
                }
            }
        }
        .navigationTitle("模态窗口演示")
    }
}

// 信息弹窗内容
struct AlertDemoView: View {
    @EnvironmentObject var router: Router
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("这是一个模态弹窗示例")
                .font(.title)
                .multilineTextAlignment(.center)
            
            Button("关闭弹窗") {
                router.dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .padding()
    }
}

// 表单弹窗内容
struct FormModalView: View {
    @EnvironmentObject var router: Router
    @State private var name = ""
    @State private var email = ""
    
    var body: some View {
        Form {
            TextField("姓名", text: $name)
            TextField("邮箱", text: $email)
                .keyboardType(.emailAddress)
            
            Button("提交") {
                print("提交表单: 姓名=\(name), 邮箱=\(email)")
                router.dismiss()
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .padding(.top)
    }
}

// 嵌套弹窗演示
struct NestedModalView: View {
    @EnvironmentObject var router: Router
    
    var body: some View {
        VStack(spacing: 20) {
            Text("第一层弹窗")
                .font(.title)
            
            Button("打开第二层弹窗") {
                router.present(id: AppPage.alertDemo) {
                    VStack {
                        Text("第二层弹窗")
                            .font(.title)
                        
                        Button("关闭当前弹窗") {
                            router.dismiss() // 只关闭当前层
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            
            Button("关闭所有弹窗") {
                // 关闭所有层级的弹窗（实际项目可能需要递归实现）
                router.dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
    }
}

// 分享功能弹窗
struct ShareSheetView: View {
    @EnvironmentObject var router: Router
    let shareText = "这是一个路由系统演示应用"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("分享内容")
                .font(.headline)
            
            Text(shareText)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            HStack {
                Button("取消") {
                    router.dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("分享") {
                    // 实际项目中可以集成UIActivityViewController
                    print("分享内容: \(shareText)")
                    router.dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding()
    }
}


// 自定义按钮样式
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
