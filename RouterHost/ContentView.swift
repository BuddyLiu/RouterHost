//
//  ContentView.swift
//  RouterHost
//
//  Created by LiuBo on 2025/8/29.
//

import SwiftUI

// -----------------------------
// 示例页面（中文注释 + 日志）
// -----------------------------
struct ContentView: View {
    @StateObject private var router = Router()
    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationContainer(router: router, rootView: HomePage())
            DebugStackView().environmentObject(router).padding()
        }
    }
}

/// 显示当前路由栈调试信息
struct DebugStackView: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(alignment: .trailing) {
            Text("Stack depth: \(router.stackIds.count)").bold()
            ForEach(Array(router.stackIds.enumerated()), id: \.offset) { idx, id in
                Text("\(idx): \(String(describing: id))")
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

// -----------------------------
// 页面示例
// -----------------------------
struct HomePage: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(spacing: 16) {
            Text("🏠 Home").font(.largeTitle)
            Button("Push Profile (id=profile)") {
                router.push(id: "profile") { ProfilePage(userName: "Taylor") }
            }
            Button("Push Details (id=42)") {
                router.push(id: 42) { DetailsPage(info: "From Home") }
            }
        }
        .padding()
    }
}

struct ProfilePage: View {
    @EnvironmentObject private var router: Router
    let userName: String
    var body: some View {
        VStack(spacing: 16) {
            Text("👤 Profile: \(userName)")
            Button("Push Settings (unique UUID) without animated") {
                router.push(id: UUID(), animated: false) { SettingsPage() }
            }
            Button("Replace Top with ReplacePage") {
                router.replaceTop(id: "replaceTop") { ReplacePage() }
            }
            Button("Pop to Root") { router.popToRoot() }
        }
        .padding()
    }
}

struct DetailsPage: View {
    @EnvironmentObject private var router: Router
    let info: String
    var body: some View {
        VStack(spacing: 16) {
            Text("ℹ️ Details: \(info)")
            Button("Push Deep (id=deep)") { router.push(id: "deep") { DeepPage() } }
            Button("Pop 1") { router.pop(count: 1) }
            Button("Pop 2") { router.pop(count: 2) }
        }
        .padding()
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(spacing: 16) {
            Text("⚙️ Settings")
            Button("Back to Root") { router.popToRoot() }
            Button("Back to Profile") { router.pop(to: "profile") }
        }
        .padding()
    }
}

struct DeepPage: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(spacing: 16) {
            Text("🧭 Deep Page")
            Button("Pop to id=42") { router.pop(to: 42) }
            Button("Pop 3 without animated") { router.pop(count: 3, animated: false) }
        }
        .padding()
    }
}

struct ReplacePage: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(spacing: 16) {
            Text("🔁 Replace Page")
            Button("Push Settings") { router.push(id: UUID()) { SettingsPage() } }
            Button("Pop to Root") { router.popToRoot() }
        }
        .padding()
    }
}
