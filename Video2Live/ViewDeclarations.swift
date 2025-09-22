import SwiftUI
import UIKit

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

// 全局共享：视频缩略图模型，供多个视图复用
struct VideoThumbnail: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let duration: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Global time segment enum for conversion logic (UI may not expose it)
enum TimeSegment: String {
    case first = "First 3s"
    case middle = "Middle 3s"
    case last = "Last 3s"
}

// 转换进度视图类型别名
typealias ConversionProgressView = Video2Live.ConversionProgressView