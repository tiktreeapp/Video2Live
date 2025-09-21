import UIKit
import Photos

extension UIImage {
    static func saveImageToPhotoLibrary(_ image: UIImage) async -> Result<String, Error> {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if success {
                    continuation.resume(returning: .success("success"))
                } else if let error = error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .failure(NSError(domain: "SaveImageError", code: -1)))
                }
            }
        }
    }
} 
