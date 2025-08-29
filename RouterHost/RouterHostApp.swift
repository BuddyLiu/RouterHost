//
//  RouterHostApp.swift
//  RouterHost
//
//  Created by LiuBo on 2025/8/29.
//

import SwiftUI

@main
struct RouterDemoApp: App {
    // 创建全局路由实例
    let router = Router()
    // 创建登录状态管理器
    let authManager = AuthManager()
    
    init() {
        // 配置全局路由
        configureRouter()
    }
    
    private func configureRouter() {
        // 设置全局导航栏样式
        router.navigationBarConfig = Router.NavigationBarConfig(
            tintColor: .systemBlue,
            barTintColor: .systemBackground,
            titleColor: .label,
            largeTitleMode: .automatic
        )
        
        // 添加登录拦截器
        let loginInterceptor = LoginInterceptor(authManager: authManager)
        router.addInterceptor(loginInterceptor)
        
        // 保存全局路由引用（可选，方便在非View层使用）
        Router.shared = router
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationContainer(router: router, rootId: AppPage.home) {
                HomeView()
            }
            .environmentObject(authManager)
        }
    }
}
