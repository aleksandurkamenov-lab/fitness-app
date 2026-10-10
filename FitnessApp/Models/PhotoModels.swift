import Foundation
import SwiftData

enum PhotoPose: String, CaseIterable, Identifiable {
    case front, side, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Отпред"
        case .side: "Отстрани"
        case .back: "Отзад"
        }
    }
}

@Model
final class ProgressPhoto {
    var date: Date = Date.now
    @Attribute(.externalStorage) var imageData: Data = Data()
    @Attribute(.externalStorage) var thumbData: Data = Data()
    var poseRaw: String = PhotoPose.front.rawValue
    /// Име на файла при внос от папка, за да не се внася два пъти.
    var sourceName: String = ""

    init(date: Date, imageData: Data, thumbData: Data, pose: PhotoPose = .front, sourceName: String = "") {
        self.date = date
        self.imageData = imageData
        self.thumbData = thumbData
        self.poseRaw = pose.rawValue
        self.sourceName = sourceName
    }

    var pose: PhotoPose {
        get { PhotoPose(rawValue: poseRaw) ?? .front }
        set { poseRaw = newValue.rawValue }
    }
}
