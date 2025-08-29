# SwiftUI UIKit Router 文档

## 1. 概述

本 Router 方案是基于 **SwiftUI + UINavigationController** 的自定义路由管理工具，适用于 iOS 15 及以上版本。它允许在 SwiftUI 中灵活进行：

* 页面 push、pop、pop 到指定页面、pop 到根页面
* 替换栈顶页面 (`replaceTop`) 或替换整个根页面 (`replaceRoot`)
* 使用唯一标识管理路由栈
* 不需要提前注册视图

同时提供 **调试面板**，显示当前路由栈状态，方便开发调试。

---

## 2. 核心功能

### 2.1 Push 页面

```swift
router.push(id: AnyHashable, builder: () -> View)
```

* 功能：向导航栈 push 一个新页面
* 参数：

  * `id`：唯一标识，可用于 `pop(to:)` 或调试
  * `builder`：返回 SwiftUI 页面
* 特点：自动注入 `router`，支持链式调用

### 2.2 Pop 页面

```swift
router.pop(count: Int = 1)
router.pop(to id: AnyHashable)
router.popToRoot()
```

* 功能：

  * `pop(count:)` 弹出指定数量的页面
  * `pop(to:)` 弹出到指定 id 的页面
  * `popToRoot()` 弹出到根页面
* 栈底不会被删除

### 2.3 替换页面

```swift
router.replaceTop(id: AnyHashable, builder: () -> View)
router.replaceRoot(id: AnyHashable, builder: () -> View)
```

* 功能：

  * `replaceTop`：替换栈顶页面（非 root 页面）
  * `replaceRoot`：替换整个导航栈为新根页面
* 注意：

  * 当栈中只有 root 时，`replaceTop` 会自动调用 `replaceRoot`
  * `replaceRoot` 禁止带动画，保证 UIKit 内部状态安全

### 2.4 栈状态调试

* `stackIds`：`@Published` 属性，保存当前导航栈 id 列表
* 可用于 UI 调试或逻辑判断

---

## 3. 运行机制

1. **UIKit + SwiftUI 混合**

   * 通过 `NavigationContainer` 封装 `UINavigationController`
   * SwiftUI 页面通过 `UIHostingController` 包装，并绑定唯一 id

2. **Router 控制导航**

   * `Router` 持有 `navigationController` 弱引用
   * push/pop/replace 都通过 UIKit API 操作栈
   * 每次操作后调用 `syncStackFromNav()` 同步栈信息

3. **主线程安全**

   * 所有 `@Published stackIds` 更新通过 `DispatchQueue.main.async` 发射，避免 SwiftUI 报错

4. **唯一标识管理**

   * 每个页面通过 `id` 唯一标识
   * 可通过 id 弹出到指定页面或替换特定页面

5. **路由日志**

   * 所有路由操作均打印到控制台，便于调试
   * 示例日志：

     ```
     ➡️ push id=profile, 当前栈深度=2
     🔁 replaceTop id=replaceTop
     ⬅️ popToRoot()
     🔁 syncStackFromNav => ["root", "profile"]
     ```

---

## 4. 使用说明

### 4.1 集成 Router

1. 创建 `Router` 实例：

```swift
@StateObject private var router = Router()
```

2. 包装根视图：

```swift
NavigationContainer(router: router, rootView: HomePage())
```

3. 在 SwiftUI 页面中注入 `router`：

```swift
@EnvironmentObject private var router: Router
```

---

### 4.2 页面操作示例

#### Push 页面

```swift
Button("Push Profile") {
    router.push(id: "profile") { ProfilePage(userName: "Taylor") }
}
```

#### Pop 页面

```swift
Button("Pop 1") { router.pop(count: 1) }
Button("Pop to Profile") { router.pop(to: "profile") }
Button("Pop to Root") { router.popToRoot() }
```

#### 替换页面

```swift
Button("Replace Top") {
    router.replaceTop(id: "replaceTop") { ReplacePage() }
}
Button("Replace Root") {
    router.replaceRoot(id: "replaceRoot") { ReplacePage() }
}
```

---

### 4.3 调试路由栈

在页面中添加 `DebugStackView` 可实时显示栈信息：

```swift
DebugStackView().environmentObject(router)
```

输出示例：

```
Stack depth: 3
0: root
1: profile
2: settings
```

---

## 5. 注意事项

1. **replaceTop 仅适用于非 root 页面**，栈中只有 root 时请使用 `replaceRoot`
2. **所有 `stackIds` 更新必须在主线程**
3. **id 必须唯一**，重复 id 可能导致行为不可预测
4. **UIKit 动画安全性**：

   * `push`、`pop` 可以带动画
   * 替换 root 时禁止动画，否则可能崩溃

---

## 6. 总结

该 Router 实现了 SwiftUI 环境下的灵活导航管理：

* 提供完整的栈操作能力
* 使用唯一 id 管理页面，支持跳转、回退、替换
* 内部使用 UIKit 保证稳定的导航动画
* 支持调试栈状态和日志追踪

适用于中大型 SwiftUI 项目，尤其需要复杂路由逻辑、跨页面跳转、返回指定页面或替换根页面的场景。
