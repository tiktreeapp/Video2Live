import Foundation
import AVFoundation
import Photos

/// Live Photo转换错误处理器 - 提供用户友好的错误信息和解决方案
class LivePhotoErrorHandler {
    
    /// 错误信息结构体
    struct ErrorInfo {
        let title: String
        let message: String
        let suggestions: [String]
        let severity: ErrorSeverity
    }
    
    /// 错误严重程度
    enum ErrorSeverity {
        case info    // 信息性错误，用户可以继续操作
        case warning // 警告性错误，建议用户注意
        case error   // 严重错误，操作无法完成
        case critical // 关键错误，需要立即处理
    }
    
    /// 分析错误并提供用户友好的信息
    static func analyzeError(_ error: Error) -> ErrorInfo {
        let nsError = error as NSError
        
        // 根据错误域和错误码进行分类处理
        switch nsError.domain {
        case "AVFoundationErrorDomain":
            return handleAVFoundationError(nsError)
        case "PHPhotosErrorDomain":
            return handlePhotosError(nsError)
        case "PreprocessingError":
            return handlePreprocessingError(error)
        case "ConversionError":
            return handleConversionError(error)
        case "ExportError":
            return handleExportError(error)
        case "SaveError":
            return handleSaveError(error)
        case "PermissionError":
            return handlePermissionError(error)
        default:
            return handleGenericError(error)
        }
    }
    
    /// 处理AVFoundation错误
    private static func handleAVFoundationError(_ error: NSError) -> ErrorInfo {
        switch error.code {
        case -11800: // AVErrorUnknown
            return ErrorInfo(
                title: "视频处理失败",
                message: "无法处理此视频文件，可能是格式不支持或文件已损坏。",
                suggestions: [
                    "尝试使用其他视频文件",
                    "检查视频文件是否完整",
                    "将视频转换为MP4格式后再试",
                    "确保视频文件没有DRM保护"
                ],
                severity: .error
            )
        case -11828: // AVErrorExportFailed
            return ErrorInfo(
                title: "视频导出失败",
                message: "视频导出过程中出现错误，可能是内存不足或存储空间不足。",
                suggestions: [
                    "清理设备存储空间",
                    "关闭其他应用释放内存",
                    "尝试降低转换质量设置",
                    "重启应用后再次尝试"
                ],
                severity: .error
            )
        case -11814: // AVErrorFileFormatNotRecognized
            return ErrorInfo(
                title: "视频格式不支持",
                message: "此视频格式不被支持，请选择MP4、MOV或M4V格式的视频。",
                suggestions: [
                    "使用MP4格式的视频文件",
                    "使用视频转换工具转换格式",
                    "从相册中选择其他视频",
                    "确保视频文件扩展名正确"
                ],
                severity: .warning
            )
        default:
            return ErrorInfo(
                title: "视频处理错误",
                message: "处理视频时出现问题：\(error.localizedDescription)",
                suggestions: [
                    "检查视频文件是否有效",
                    "尝试使用其他视频文件",
                    "联系技术支持获取帮助"
                ],
                severity: .error
            )
        }
    }
    
    /// 处理照片库错误
    private static func handlePhotosError(_ error: NSError) -> ErrorInfo {
        switch error.code {
        case -1: // 一般权限错误
            return ErrorInfo(
                title: "照片库权限被拒绝",
                message: "需要照片库权限才能保存Live Photo，请在设置中开启权限。",
                suggestions: [
                    "进入设置 > 隐私与安全性 > 照片",
                    "找到此应用并选择\"所有照片\"",
                    "重启应用后再次尝试",
                    "确保iCloud照片库已正确配置"
                ],
                severity: .critical
            )
        case 3300: // PHPhotosErrorNotAuthorized
            return ErrorInfo(
                title: "没有照片访问权限",
                message: "应用没有访问照片的权限，无法保存转换结果。",
                suggestions: [
                    "在设置中开启照片访问权限",
                    "选择\"所有照片\"访问级别",
                    "检查屏幕使用时间限制",
                    "确保设备有足够的存储空间"
                ],
                severity: .critical
            )
        default:
            return ErrorInfo(
                title: "照片库错误",
                message: "访问照片库时出现问题：\(error.localizedDescription)",
                suggestions: [
                    "检查照片库权限设置",
                    "确保设备存储空间充足",
                    "尝试重启设备",
                    "检查iCloud照片同步状态"
                ],
                severity: .error
            )
        }
    }
    
    /// 处理预处理错误
    private static func handlePreprocessingError(_ error: Error) -> ErrorInfo {
        if let preprocessingError = error as? PreprocessingError {
            switch preprocessingError {
            case .fileNotFound:
                return ErrorInfo(
                    title: "视频文件不存在",
                    message: "选择的视频文件无法找到，可能已被删除或移动。",
                    suggestions: [
                        "重新选择视频文件",
                        "检查文件是否存在于相册",
                        "尝试从文件应用中选择",
                        "确保视频文件没有被其他应用锁定"
                    ],
                    severity: .error
                )
            case .fileTooSmall:
                return ErrorInfo(
                    title: "视频文件太小",
                    message: "视频文件太小（小于0.1MB），可能不是有效的视频文件。",
                    suggestions: [
                        "选择更大的视频文件",
                        "检查文件是否为有效的视频格式",
                        "尝试使用其他视频文件",
                        "确保文件没有损坏"
                    ],
                    severity: .warning
                )
            case .videoTooShort:
                return ErrorInfo(
                    title: "视频时长太短",
                    message: "视频时长太短（小于1秒），无法制作有效的Live Photo。",
                    suggestions: [
                        "选择时长至少1秒的视频",
                        "建议使用1-5秒的视频获得最佳效果",
                        "检查视频文件是否完整",
                        "尝试使用其他视频文件"
                    ],
                    severity: .warning
                )
            case .noVideoTrack:
                return ErrorInfo(
                    title: "没有视频轨道",
                    message: "此文件不包含视频轨道，可能是音频文件或损坏的视频。",
                    suggestions: [
                        "确保选择的是视频文件",
                        "检查文件扩展名是否为.mp4、.mov等",
                        "尝试使用其他视频文件",
                        "使用视频播放器确认文件可正常播放"
                    ],
                    severity: .error
                )
            case .exportFailed:
                return ErrorInfo(
                    title: "视频导出失败",
                    message: "视频导出过程中出现错误，可能是内存不足或格式不支持。",
                    suggestions: [
                        "尝试降低转换质量设置",
                        "关闭其他应用释放内存",
                        "检查设备存储空间",
                        "重启应用后再次尝试"
                    ],
                    severity: .error
                )
            default:
                return ErrorInfo(
                    title: "预处理失败",
                    message: "视频预处理失败：\(error.localizedDescription)",
                    suggestions: [
                        "检查视频文件格式",
                        "尝试使用其他视频文件",
                        "降低转换质量设置",
                        "联系技术支持"
                    ],
                    severity: .error
                )
            }
        }
        return handleGenericError(error)
    }
    
    /// 处理转换错误
    private static func handleConversionError(_ error: Error) -> ErrorInfo {
        return ErrorInfo(
            title: "Live Photo转换失败",
            message: "将视频转换为Live Photo时出现问题：\(error.localizedDescription)",
            suggestions: [
                "检查视频格式是否支持",
                "尝试降低转换质量设置",
                "确保视频文件没有损坏",
                "尝试使用较短的片段"
            ],
            severity: .error
        )
    }
    
    /// 处理导出错误
    private static func handleExportError(_ error: Error) -> ErrorInfo {
        return ErrorInfo(
            title: "视频导出失败",
            message: "视频导出过程中出现错误：\(error.localizedDescription)",
            suggestions: [
                "检查设备存储空间",
                "关闭其他应用释放内存",
                "尝试降低视频分辨率",
                "重启应用后再次尝试"
            ],
            severity: .error
        )
    }
    
    /// 处理保存错误
    private static func handleSaveError(_ error: Error) -> ErrorInfo {
        return ErrorInfo(
            title: "保存失败",
            message: "无法将Live Photo保存到相册：\(error.localizedDescription)",
            suggestions: [
                "检查照片库权限设置",
                "确保设备有足够的存储空间",
                "检查iCloud照片同步状态",
                "尝试保存到本地相册"
            ],
            severity: .error
        )
    }
    
    /// 处理权限错误
    private static func handlePermissionError(_ error: Error) -> ErrorInfo {
        return ErrorInfo(
            title: "权限被拒绝",
            message: "应用需要相应的权限才能正常工作：\(error.localizedDescription)",
            suggestions: [
                "进入设置 > 隐私与安全性",
                "找到此应用并开启所需权限",
                "重启应用后再次尝试",
                "检查屏幕使用时间限制"
            ],
            severity: .critical
        )
    }
    
    /// 处理通用错误
    private static func handleGenericError(_ error: Error) -> ErrorInfo {
        let nsError = error as NSError
        return ErrorInfo(
            title: "操作失败",
            message: "发生未知错误：\(error.localizedDescription)",
            suggestions: [
                "检查网络连接",
                "重启应用后再次尝试",
                "确保设备系统为最新版本",
                "联系技术支持并提供错误信息"
            ],
            severity: .error
        )
    }
    
    /// 获取错误处理建议
    static func getErrorSuggestions(for error: Error) -> [String] {
        let errorInfo = analyzeError(error)
        return errorInfo.suggestions
    }
    
    /// 格式化错误信息用于显示
    static func formatErrorForDisplay(_ error: Error) -> String {
        let errorInfo = analyzeError(error)
        var formattedMessage = "**\(errorInfo.title)**\n\n"
        formattedMessage += "\(errorInfo.message)\n\n"
        
        if !errorInfo.suggestions.isEmpty {
            formattedMessage += "**建议解决方案：**\n"
            for (index, suggestion) in errorInfo.suggestions.enumerated() {
                formattedMessage += "\(index + 1). \(suggestion)\n"
            }
        }
        
        return formattedMessage
    }
    
    /// 检查错误是否可以通过重试解决
    static func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // 可重试的错误类型
        let retryableErrorCodes = [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet
        ]
        
        if nsError.domain == NSURLErrorDomain && retryableErrorCodes.contains(nsError.code) {
            return true
        }
        
        // 某些AVFoundation错误也可以重试
        if nsError.domain == "AVFoundationErrorDomain" {
            switch nsError.code {
            case -11800, -11828: // 未知错误和导出失败
                return true
            default:
                break
            }
        }
        
        return false
    }
    
    /// 获取错误的严重程度
    static func getErrorSeverity(_ error: Error) -> ErrorSeverity {
        let errorInfo = analyzeError(error)
        return errorInfo.severity
    }
}

/// 扩展：为NSError添加便利方法
extension NSError {
    /// 获取用户友好的错误描述
    var userFriendlyDescription: String {
        return LivePhotoErrorHandler.formatErrorForDisplay(self)
    }
    
    /// 获取错误建议
    var errorSuggestions: [String] {
        return LivePhotoErrorHandler.getErrorSuggestions(for: self)
    }
    
    /// 检查是否可以重试
    var isRetryable: Bool {
        return LivePhotoErrorHandler.isRetryableError(self)
    }
}