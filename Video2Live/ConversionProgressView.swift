import SwiftUI
import Photos

// 空文件 - ConversionProgressView已移至ViewDeclarations.swift

#Preview {
    ConversionProgressView(
        isPresented: .constant(true),
        previewImages: [
            UIImage(systemName: "photo")!,
            UIImage(systemName: "video")!
        ],
        onConversionStart: { progressHandler, completionHandler in
            // 模拟转换过程
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                progressHandler(0.5, 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                completionHandler(.success(["asset1", "asset2"]))
            }
        }
    )
}