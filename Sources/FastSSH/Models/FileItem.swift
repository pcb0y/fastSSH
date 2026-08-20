import Foundation

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modTime: Date
    let permissions: String
}
