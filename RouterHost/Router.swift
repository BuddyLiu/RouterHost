//
//  Router.swift
//  RouterHost
//
//  Created by LiuBo on 2025/8/29.
//

//
//  Router.swift
//  RouterHost
//
//  Created by LiuBo on 2025/8/29.
//

import SwiftUI

// MARK: - 页面标识协议定义，增强类型安全
/// 所有页面ID必须实现此协议，替代原AnyHashable，提升类型安全
protocol PageIdentifier: Hashable {
    /// 页面的描述性名称，用于调试日志
    var description: String { get }
    
    /// 用于协议类型比较的方法
    func isEqual(to other: any PageIdentifier) -> Bool
}

// 为所有实现PageIdentifier的类型提供默认实现
extension PageIdentifier {
    func isEqual(to other: any PageIdentifier) -> Bool {
        // 先检查类型是否相同
        guard let other = other as? Self else { return false }
        // 再比较值
        return self == other
    }
}

// MARK: - AnyHostingController
/// 自定义UIHostingController，用于包装SwiftUI View，并绑定唯一id便于路由管理
final class AnyHostingController: UIHostingController<AnyView> {
    /// 唯一标识，用于pop(to:)或调试
    let id: any PageIdentifier
    /// 弱引用Router，便于在View中触发路由操作，避免循环引用
    weak var router: Router?
    
    /// 初始化方法
    init(id: any PageIdentifier, rootView: AnyView, router: Router) {
        self.id = id
        self.router = router
        super.init(rootView: rootView)
        applyNavigationBarConfig(router.navigationBarConfig)
    }
    
    /// 应用导航栏配置
    func applyNavigationBarConfig(_ config: Router.NavigationBarConfig) {
        navigationItem.largeTitleDisplayMode = config.largeTitleMode
        navigationController?.navigationBar.tintColor = config.tintColor
        navigationController?.navigationBar.barTintColor = config.barTintColor
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: config.titleColor
        ]
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - 路由拦截器协议
/// 用于在导航操作执行前进行拦截处理
protocol RouterInterceptor: AnyObject {
    /// 拦截push操作
    /// - Parameter id: 目标页面ID
    /// - Returns: 是否允许执行push
    func shouldPush(to id: any PageIdentifier) -> Bool
    
    /// 拦截pop操作
    /// - Parameter id: 目标页面ID
    /// - Returns: 是否允许执行pop
    func shouldPop(to id: any PageIdentifier) -> Bool
    
    /// 拦截present操作（新增）
    /// - Parameter id: 目标页面ID
    /// - Returns: 是否允许执行present
    func shouldPresent(to id: any PageIdentifier) -> Bool
    
    /// 拦截dismiss操作（新增）
    /// - Parameter id: 当前模态页面ID（如果有）
    /// - Returns: 是否允许执行dismiss
    func shouldDismiss(currentId: (any PageIdentifier)?) -> Bool
}

// 为拦截器协议提供默认实现（新增）
// 这样已有的拦截器不需要强制实现新方法
extension RouterInterceptor {
    func shouldPresent(to id: any PageIdentifier) -> Bool {
        return true // 默认允许所有present操作
    }
    
    func shouldDismiss(currentId: (any PageIdentifier)?) -> Bool {
        return true // 默认允许所有dismiss操作
    }
}

// MARK: - Router（UIKit-driven）
/// 路由管理器，封装所有导航操作
@MainActor
final class Router: ObservableObject {
    
    static var shared: Router? = nil
    
    /// 导航栏配置模型
    struct NavigationBarConfig {
        var tintColor: UIColor = .systemBlue
        var barTintColor: UIColor = .systemBackground
        var titleColor: UIColor = .label
        var largeTitleMode: UINavigationItem.LargeTitleDisplayMode = .automatic
    }
    
    /// UINavigationController引用
    fileprivate weak var navigationController: UINavigationController?
    
    /// 当前路由栈ID列表
    @Published private(set) var stackIds: [any PageIdentifier] = []
    
    /// 当前模态栈ID记录（新增）
    /// 用于跟踪模态页面层级，支持多级模态拦截
    @Published private(set) var modalStackIds: [any PageIdentifier] = []
    
    /// 导航栏全局配置
    @Published var navigationBarConfig = NavigationBarConfig()
    
    /// 路由拦截器数组
    private var interceptors: [RouterInterceptor] = []
    
    /// 添加路由拦截器
    func addInterceptor(_ interceptor: RouterInterceptor) {
        interceptors.append(interceptor)
    }
    
    /// 移除路由拦截器
    func removeInterceptor(_ interceptor: RouterInterceptor) {
        interceptors.removeAll { $0 === interceptor }
    }
    
    /// 设置UINavigationController引用
    func setNavigationController(_ nav: UINavigationController) {
        self.navigationController = nav
        syncStackFromNav(nav)
        // 监听模态页面消失事件（新增）
        setupModalDismissObserver()
    }
    
    /// 监听模态页面消失事件（新增）
    private func setupModalDismissObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modalDismissed),
            name: UIWindow.didBecomeHiddenNotification,
            object: nil
        )
    }
    
    /// 处理模态页面消失事件（新增）
    @objc private func modalDismissed(notification: NSNotification) {
        guard let nav = navigationController,
              nav.presentedViewController == nil,
              !modalStackIds.isEmpty else { return }
        
        // 移除最后一个模态页面ID
        modalStackIds.removeLast()
        print("🔁 模态栈同步：\(modalStackIds.map { $0.description })")
    }
    
    // MARK: - Push操作
    /// 推入一个新页面
    func push<V: View>(
        id: any PageIdentifier,
        animated: Bool = true,
        @ViewBuilder _ builder: @escaping () -> V
    ) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行push")
            return
        }
        
        // 检查ID是否已存在（使用自定义的比较方法）
        if stackIds.contains(where: { $0.isEqual(to: id) }) {
            print("⚠️ 路由警告：ID为\(id.description)的页面已存在于当前栈中，可能导致导航异常")
        }
        
        // 执行拦截器检查
        let canPush = interceptors.allSatisfy { $0.shouldPush(to: id) }
        guard canPush else {
            print("⚠️ 路由拦截：拦截到前往\(id.description)的push操作")
            return
        }
        
        // 创建并推入新页面
        let host = AnyHostingController(
            id: id,
            rootView: AnyView(builder().environmentObject(self)),
            router: self
        )
        nav.pushViewController(host, animated: animated)
        
        // 同步栈信息
        syncStackFromNav(nav)
        print("➡️ 路由push：\(id.description)，当前栈深度=\(stackIds.count)")
    }
    
    // MARK: - Pop操作
    /// 弹出若干个页面
    func pop(count: Int = 1, animated: Bool = true) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行pop")
            return
        }
        
        let vcCount = nav.viewControllers.count
        let targetIndex = max(0, vcCount - 1 - count)
        let targetVC = nav.viewControllers[targetIndex]
        
        // 获取目标页面ID用于拦截检查
        let targetId: any PageIdentifier = (targetVC as? AnyHostingController)?.id ?? UnknownPageId()
        
        // 执行拦截器检查
        let canPop = interceptors.allSatisfy { $0.shouldPop(to: targetId) }
        guard canPop else {
            print("⚠️ 路由拦截：拦截到弹出到\(targetId.description)的pop操作")
            return
        }
        
        // 执行pop操作
        if targetIndex == 0 {
            nav.popToRootViewController(animated: animated)
            print("⬅️ 路由pop：返回根页面，弹出了\(vcCount - 1)个页面")
        } else {
            nav.popToViewController(targetVC, animated: animated)
            print("⬅️ 路由pop：弹出\(count)个页面，到达\(targetId.description)")
        }
        syncStackFromNav(nav)
    }
    
    /// 弹出到指定ID的页面
    func pop(to id: any PageIdentifier, animated: Bool = true) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行pop(to:)")
            return
        }
        
        // 执行拦截器检查
        let canPop = interceptors.allSatisfy { $0.shouldPop(to: id) }
        guard canPop else {
            print("⚠️ 路由拦截：拦截到弹出到\(id.description)的pop操作")
            return
        }
        
        // 查找目标页面（使用自定义的比较方法）
        if let targetVC = nav.viewControllers.first(where: {
            guard let hostVC = $0 as? AnyHostingController else { return false }
            return hostVC.id.isEqual(to: id)
        }) {
            nav.popToViewController(targetVC, animated: animated)
            print("⬅️ 路由pop：到达指定页面\(id.description)")
            syncStackFromNav(nav)
        } else {
            print("⚠️ 路由错误：未找到ID为\(id.description)的页面")
        }
    }
    
    /// 弹出到根页面
    func popToRoot(animated: Bool = true) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行popToRoot")
            return
        }
        
        // 获取根页面ID用于拦截检查
        let rootId: any PageIdentifier = stackIds.first ?? UnknownPageId()
        
        // 执行拦截器检查
        let canPop = interceptors.allSatisfy { $0.shouldPop(to: rootId) }
        guard canPop else {
            print("⚠️ 路由拦截：拦截到返回根页面\(rootId.description)的操作")
            return
        }
        
        nav.popToRootViewController(animated: animated)
        print("⬅️ 路由pop：返回根页面")
        syncStackFromNav(nav)
    }
    
    // MARK: - 替换页面操作
    /// 替换栈顶页面，如果只有root，则调用replaceRoot
    func replaceTop<V: View>(
        id: any PageIdentifier,
        animated: Bool = true,
        @ViewBuilder _ builder: @escaping () -> V
    ) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行replaceTop")
            return
        }
        
        guard nav.viewControllers.count > 1 else {
            // 栈里只有root时，安全替换root
            replaceRoot(id: id, animated: animated, builder)
            return
        }
        
        // 检查ID是否已存在（除栈顶外）
        let existingIds = stackIds.dropLast()
        if existingIds.contains(where: { $0.isEqual(to: id) }) {
            print("⚠️ 路由警告：ID为\(id.description)的页面已存在于当前栈中，可能导致导航异常")
        }
        
        var vcs = nav.viewControllers
        let newVC = AnyHostingController(
            id: id,
            rootView: AnyView(builder().environmentObject(self)),
            router: self
        )
        vcs[vcs.count - 1] = newVC
        nav.setViewControllers(vcs, animated: animated)
        syncStackFromNav(nav)
        print("🔁 路由替换：替换栈顶为\(id.description)")
    }
    
    /// 替换整个栈为新root页面
    func replaceRoot<V: View>(
        id: any PageIdentifier,
        animated: Bool = true,
        @ViewBuilder _ builder: @escaping () -> V
    ) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行replaceRoot")
            return
        }
        
        let newRoot = AnyHostingController(
            id: id,
            rootView: AnyView(builder().environmentObject(self)),
            router: self
        )
        nav.setViewControllers([newRoot], animated: animated)
        syncStackFromNav(nav)
        print("🔁 路由替换：替换根页面为\(id.description)")
    }
    
    // MARK: - 模态弹窗操作
    /// 模态展示页面
    func present<V: View>(
        id: any PageIdentifier,
        animated: Bool = true,
        modalPresentationStyle: UIModalPresentationStyle = .automatic,
        @ViewBuilder _ builder: @escaping () -> V
    ) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行present")
            return
        }
        
        // 执行拦截器检查（新增）
        let canPresent = interceptors.allSatisfy { $0.shouldPresent(to: id) }
        guard canPresent else {
            print("⚠️ 路由拦截：拦截到展示\(id.description)的present操作")
            return
        }
        
        let hostVC = AnyHostingController(
            id: id,
            rootView: AnyView(builder().environmentObject(self)),
            router: self
        )
        let modalNav = UINavigationController(rootViewController: hostVC)
        modalNav.navigationBar.tintColor = navigationBarConfig.tintColor
        modalNav.modalPresentationStyle = modalPresentationStyle
        nav.present(modalNav, animated: animated)
        
        // 记录模态页面ID（新增）
        modalStackIds.append(id)
        print("📱 路由模态：展示\(id.description)，当前模态栈深度=\(modalStackIds.count)")
    }
    
    /// 关闭当前模态页面
    func dismiss(animated: Bool = true) {
        guard let nav = navigationController else {
            print("⚠️ 路由错误：未绑定UINavigationController，无法执行dismiss")
            return
        }
        
        // 获取当前模态页面ID（新增）
        let currentModalId = modalStackIds.last
        
        // 执行拦截器检查（新增）
        let canDismiss = interceptors.allSatisfy { $0.shouldDismiss(currentId: currentModalId) }
        guard canDismiss else {
            print("⚠️ 路由拦截：拦截到关闭\(currentModalId?.description ?? "未知")的dismiss操作")
            return
        }
        
        if nav.presentedViewController != nil {
            nav.dismiss(animated: animated) { [weak self] in
                guard let self = self, !self.modalStackIds.isEmpty else { return }
                // 移除最后一个模态页面ID
                self.modalStackIds.removeLast()
                print("📱 路由模态：关闭当前模态页面，剩余模态栈深度=\(self.modalStackIds.count)")
            }
        } else {
            print("⚠️ 路由警告：当前没有模态页面可关闭")
        }
    }
    
    // MARK: - 栈信息同步
    /// 从UINavigationController同步当前栈id
    fileprivate func syncStackFromNav(_ nav: UINavigationController) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let ids: [any PageIdentifier] = nav.viewControllers.compactMap { vc -> (any PageIdentifier)? in
                if let hostVC = vc as? AnyHostingController {
                    return hostVC.id
                } else {
                    let className = String(describing: type(of: vc))
                    return UnknownPageId(className: className)
                }
            }
            self.stackIds = ids
            print("🔁 路由栈同步：\(ids.map { $0.description })")
        }
    }
    
    /// 外部同步栈id
    fileprivate func syncStack(with ids: [any PageIdentifier]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stackIds = ids
            print("🔁 路由栈同步：\(ids.map { $0.description })")
        }
    }
}

// MARK: - 未知页面ID（用于非SwiftUI页面）
private struct UnknownPageId: PageIdentifier {
    let className: String
    
    init(className: String = "Unknown") {
        self.className = className
    }
    
    var description: String {
        "UnknownPage(\(className))"
    }
}

// MARK: - NavigationContainer
/// SwiftUI封装UINavigationController，承载Router
struct NavigationContainer<Root: View>: UIViewControllerRepresentable {
    @ObservedObject var router: Router
    let rootView: Root
    let rootId: any PageIdentifier
    
    /// 初始化方法
    init(
        router: Router,
        rootId: any PageIdentifier,
        @ViewBuilder rootView: () -> Root
    ) {
        self.router = router
        self.rootId = rootId
        self.rootView = rootView()
    }
    
    func makeUIViewController(context: Context) -> UINavigationController {
        // 创建根页面容器
        let rootHost = AnyHostingController(
            id: rootId,
            rootView: AnyView(rootView.environmentObject(router)),
            router: router
        )
        let nav = UINavigationController(rootViewController: rootHost)
        nav.delegate = context.coordinator
        router.setNavigationController(nav)
        return nav
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // 更新rootView
        if let rootHost = uiViewController.viewControllers.first as? AnyHostingController {
            rootHost.rootView = AnyView(rootView.environmentObject(router))
            rootHost.applyNavigationBarConfig(router.navigationBarConfig)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(router: router)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate {
        let router: Router
        
        init(router: Router) {
            self.router = router
        }
        
        /// 每次完成push/pop都同步栈id
        func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            let ids: [any PageIdentifier] = navigationController.viewControllers.compactMap { vc -> (any PageIdentifier)? in
                if let hostVC = vc as? AnyHostingController {
                    return hostVC.id
                } else {
                    let className = String(describing: type(of: vc))
                    return UnknownPageId(className: className)
                }
            }
            router.syncStack(with: ids)
        }
    }
}
