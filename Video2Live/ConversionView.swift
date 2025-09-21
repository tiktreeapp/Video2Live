import SwiftUI
import Photos

// 转换状态枚举
enum ConversionState {
    case ready
    case converting(progress: Double)  // 转换中，带进度
    case completed                     // 转换完成
}

struct ConversionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @State private var conversionState: ConversionState = .ready
    let previewImage: UIImage
    let onConversionStart: (@escaping (Double) -> Void, @escaping (Result<Void, Error>) -> Void) -> Void
    
    private var resultMessage: String {
        switch conversionState {
        case .ready:
            return "选择视频后点击转换按钮"
        case .converting(let progress):
            return "正在处理中... \(Int(progress * 100))%"
        case .completed:
            return "已成功创建Live Photo! 可在相册中查看。"
        }
    }
    
    var body: some View {
        VStack {
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)
                .cornerRadius(10)

            Text(resultMessage)
                .padding()

            if case let .converting(progress) = conversionState {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding()
            }

            if conversionState == .ready {
                Button(action: {
                    onConversionStart(
                        { progress in
                            withAnimation {
                                conversionState = .converting(progress: progress)
                            }
                        },
                        { result in
                            withAnimation {
                                switch result {
                                case .success:
                                    conversionState = .completed
                                case .failure(let error):
                                    print("转换失败: \(error)")
                                    conversionState = .ready
                                }
                            }
                        }
                    )
                }) {
                    Text("开始转换")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }

            if conversionState == .completed {
                Button("完成") {
                    dismiss()
                }
                .padding()
            }
        }
    }
}

// 预览
#Preview {
    ConversionView(
        isPresented: .constant(true),
        previewImage: UIImage(systemName: "photo") ?? UIImage(),
        onConversionStart: { progressHandler, completionHandler in
            // 预览中不执行实际转换
        }
    )
} 
