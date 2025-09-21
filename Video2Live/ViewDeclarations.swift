import SwiftUI

// 视图声明文件 - 解决scope识别问题
// 使用类型别名来确保跨文件识别

// 基本视图协议，所有自定义视图都遵循
protocol AppView: View {
    associatedtype Content: View
    var content: Content { get }
}

// 为视图提供统一的标识
extension View {
    var viewIdentifier: String {
        return String(describing: type(of: self))
    }
}