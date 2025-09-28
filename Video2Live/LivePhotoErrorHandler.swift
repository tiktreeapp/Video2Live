import Foundation

struct LivePhotoErrorHandler {
    struct ErrorInfo {
        let title: String
        let message: String
        let suggestions: [String]
    }

    static func analyzeError(_ error: Error) -> ErrorInfo {
        let nsError = error as NSError
        let title = "发生错误 (\(nsError.domain) - \(nsError.code))"
        let message = nsError.localizedDescription.isEmpty ? "\(error)" : nsError.localizedDescription
        var suggestions: [String] = []

        switch nsError.domain {
        case "PermissionError", "PHPhotosErrorDomain":
            suggestions.append(contentsOf: [
                "前往 设置 > 隐私 > 照片，授予本应用“所有照片”权限",
                "若已授权但仍失败，重启应用后重试"
            ])
        case "ExportError":
            suggestions.append(contentsOf: [
                "检查可用存储空间是否充足",
                "避免选择损坏或过短（<1秒）的视频",
                "尝试转换其他视频以排除源文件问题"
            ])
        case "FileNotFound":
            suggestions.append("视频源文件不存在或已被系统清理，请重新选择视频")
        case "InvalidVideo":
            suggestions.append("视频文件没有有效视频轨道，请更换为标准格式（.mov/.mp4）")
        default:
            break
        }

        // 通用建议兜底
        suggestions.append(contentsOf: [
            "避免选择极短或极小体积的视频",
            "切换“转换质量”为 平衡/快速 再试",
            "重启应用或重启设备后再次尝试"
        ])

        return ErrorInfo(title: title, message: message, suggestions: suggestions)
    }

    static func formatErrorForDisplay(_ error: Error) -> String {
        let info = analyzeError(error)
        let sug = info.suggestions.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        return "\(info.title)\n\n\(info.message)\n\n建议：\n\(sug)"
    }
}