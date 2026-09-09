import Foundation
import Metal

/// Decode one photograph at a time away from the display thread. Rapid navigation
/// discards queued obsolete requests; only the latest result reaches the renderer.
final class PhotoLoader {
    private let queue = DispatchQueue(label: "Sokak.photo-decode", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private let decode: (URL) throws -> MTLTexture

    init(decode: @escaping (URL) throws -> MTLTexture) { self.decode = decode }

    @discardableResult func cancel() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }
    private func isCurrent(_ request: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return request == generation
    }
    func load(_ url: URL, completion: @escaping (Result<MTLTexture, Error>) -> Void) {
        let request = cancel()
        queue.async { [weak self] in
            guard let self, self.isCurrent(request) else { return }
            let result = autoreleasepool { Result { try self.decode(url) } }
            DispatchQueue.main.async { [weak self] in
                guard self?.isCurrent(request) == true else { return }
                completion(result)
            }
        }
    }
}
