//
//  Router.swift
//  RouterHost
//
//  Created by LiuBo on 2025/8/29.
//

import SwiftUI

// -----------------------------
// AnyHostingController
// -----------------------------
/// 自定义 UIHostingController，用于包装任意 SwiftUI View，并绑定唯一 id 便于路由管理
final class AnyHostingController: UIHostingController<AnyView> {
    /// 唯一标识，用于 pop(to:) 或调试
    let id: AnyHashable
    /// 弱引用 Router，便于在 View 中触发路由操作
    weak var router: Router?
    
    init(id: AnyHashable, rootView: AnyView, router: Router) {
        self.id = id
        self.router = router
        super.init(rootView: rootView)
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:)") }
}

// -----------------------------
// Router（UIKit-driven）
// -----------------------------
@MainActor
final class Router: ObservableObject {
    /// UINavigationController 引用，用于 UIKit push/pop
    fileprivate weak var navigationController: UINavigationController?
    
    /// 当前路由栈 id 列表，用于调试
    @Published private(set) var stackIds: [AnyHashable] = []
    
    /// 设置 UINavigationController 引用，并同步栈信息
    func setNavigationController(_ nav: UINavigationController) {
        self.navigationController = nav
        syncStackFromNav(nav)
    }
    
    // MARK: - Push
    /// 推入一个新页面
    func push<V: View>(id: AnyHashable, @ViewBuilder _ builder: @escaping () -> V) {
        guard let nav = navigationController else { return }
        
        let host = AnyHostingController(
            id: id,
            rootView: AnyView(builder().environmentObject(self)), // 注入 router
            router: self
        )
        nav.pushViewController(host, animated: true)
        
        // 同步栈
        syncStackFromNav(nav)
        print("➡️ push id=\(id), 当前栈深度=\(stackIds.count)")
    }
    
    // MARK: - Pop
    /// 弹出若干个页面
    func pop(count: Int = 1) {
        guard let nav = navigationController else { return }
        let vcCount = nav.viewControllers.count
        let targetIndex = max(0, vcCount - 1 - count)
        
        if targetIndex == 0 {
            nav.popToRootViewController(animated: true)
            print("⬅️ popToRoot (count=\(count))")
        } else {
            let targetVC = nav.viewControllers[targetIndex]
            nav.popToViewController(targetVC, animated: true)
            print("⬅️ pop count=\(count)")
        }
        syncStackFromNav(nav)
    }
    
    /// 弹出到指定 id 页面
    func pop(to id: AnyHashable) {
        guard let nav = navigationController else { return }
        if let targetVC = nav.viewControllers.reversed().first(where: { ($0 as? AnyHostingController)?.id == id }) {
            nav.popToViewController(targetVC, animated: true)
            print("⬅️ pop(to: \(id))")
            syncStackFromNav(nav)
        } else {
            print("⚠️ pop(to:) 未找到 id=\(id)")
        }
    }
    
    /// 弹出到根页面
    func popToRoot() {
        guard let nav = navigationController else { return }
        nav.popToRootViewController(animated: true)
        print("⬅️ popToRoot()")
        syncStackFromNav(nav)
    }
    
    // MARK: - Replace
    /// 替换栈顶页面，如果只有 root，则调用 replaceRoot
    func replaceTop<V: View>(id: AnyHashable, @ViewBuilder _ builder: @escaping () -> V) {
        guard let nav = navigationController else { return }
        
        guard nav.viewControllers.count > 1 else {
            // 栈里只有 root 时，安全替换 root
            replaceRoot(id: id, builder)
            return
        }
        
        var vcs = nav.viewControllers
        let newVC = AnyHostingController(id: id, rootView: AnyView(builder().environmentObject(self)), router: self)
        vcs[vcs.count - 1] = newVC
        nav.setViewControllers(vcs, animated: true)
        syncStackFromNav(nav)
        print("🔁 replaceTop id=\(id)")
    }
    
    /// 替换整个栈为新 root 页面
    func replaceRoot<V: View>(id: AnyHashable, @ViewBuilder _ builder: @escaping () -> V) {
        guard let nav = navigationController else { return }
        let newRoot = AnyHostingController(id: id, rootView: AnyView(builder().environmentObject(self)), router: self)
        nav.setViewControllers([newRoot], animated: true)
        syncStackFromNav(nav)
        print("🔁 replaceRoot id=\(id)")
    }
    
    // MARK: - 同步栈信息
    /// 从 UINavigationController 同步当前栈 id（主线程安全）
    fileprivate func syncStackFromNav(_ nav: UINavigationController) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let ids = nav.viewControllers.compactMap { ($0 as? AnyHostingController)?.id }
            self.stackIds = ids
            print("🔁 syncStackFromNav => \(ids)")
        }
    }
    
    /// 外部同步栈 id（主线程安全）
    fileprivate func syncStack(with ids: [AnyHashable]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stackIds = ids
            print("🔁 syncStack(with:) => \(ids)")
        }
    }
}

// -----------------------------
// NavigationContainer
// -----------------------------
/// SwiftUI 封装 UINavigationController，承载 Router
struct NavigationContainer<Root: View>: UIViewControllerRepresentable {
    @ObservedObject var router: Router
    let rootView: Root
    
    func makeUIViewController(context: Context) -> UINavigationController {
        // rootHost 用于初始化导航栈
        let rootHost = AnyHostingController(
            id: "root",
            rootView: AnyView(rootView.environmentObject(router)),
            router: router
        )
        let nav = UINavigationController(rootViewController: rootHost)
        nav.delegate = context.coordinator
        router.setNavigationController(nav)
        return nav
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // 更新 rootView（SwiftUI 视图状态变化时刷新）
        if let rootHost = uiViewController.viewControllers.first as? AnyHostingController {
            rootHost.rootView = AnyView(rootView.environmentObject(router))
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(router: router) }
    
    class Coordinator: NSObject, UINavigationControllerDelegate {
        let router: Router
        init(router: Router) { self.router = router }
        
        /// 每次完成 push/pop 都同步栈 id
        func navigationController(_ navigationController: UINavigationController,
                                  didShow viewController: UIViewController,
                                  animated: Bool) {
            let ids = navigationController.viewControllers.compactMap { ($0 as? AnyHostingController)?.id }
            DispatchQueue.main.async {
                self.router.syncStack(with: ids)
            }
        }
    }
}

