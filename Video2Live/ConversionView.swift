import SwiftUI
import Photos

// 转换状态枚举
enum ConversionFlowState {
    case ready
    case converting(progress: Double)  // 转换中，带进度
    case completed                     // 转换完成
}

struct ConversionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @State private var conversionState: ConversionFlowState = .ready
    let previewImage: UIImage
    let onConversionStart: (@escaping (Double) -> Void, @escaping (Result<Void, Error>) -> Void) -> Void
    
    private var resultMessage: String {
        switch conversionState {
        case .ready:
            return "Select a video and tap Convert"
        case .converting(let progress):
            return "Processing... \(Int(progress * 100))%"
        case .completed:
            return "Live Photo created! You can view it in Photos."
        }
    }
    
    var body: some View {
        VStack {
            // Auto-start conversion when the sheet appears to avoid a blank page
            Color.clear
                .frame(height: 0)
                .onAppear {
                    if case .ready = conversionState {
                        withAnimation {
                            conversionState = .converting(progress: 0)
                        }
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
                                        print("Conversion failed: \(error)")
                                        conversionState = .ready
                                    }
                                }
                            }
                        )
                    }
                }
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

            if case .ready = conversionState {
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
                                    print("Conversion failed: \(error)")
                                    conversionState = .ready
                                }
                            }
                        }
                    )
                }) {
                    Text("Start Conversion")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }

            if case .completed = conversionState {
                VStack {
                    Button("Close") {
                        dismiss()
                    }
                    .padding()
                    
                    Button("View in Photos") {
                        if let photosURL = URL(string: "photos-redirect://") {
                            UIApplication.shared.open(photosURL)
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
