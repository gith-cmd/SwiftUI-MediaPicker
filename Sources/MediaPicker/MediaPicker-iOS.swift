//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftUI FoodTracker tutorial series
//
// Copyright (c) 2020-2021 AppDev@UW.edu and the SwiftUI MediaPicker authors
// Licensed under MIT License
//
// See https://github.com/UWAppDev/SwiftUI-MediaPicker/blob/main/LICENSE
// for license information
// See https://github.com/UWAppDev/SwiftUI-MediaPicker/graphs/contributors
// for the list of SwiftUI MediaPicker project authors
//
//===----------------------------------------------------------------------===//

#if os(iOS)
import SwiftUI
import struct PhotosUI.PHPickerResult
@_implementationOnly import UniformTypeIdentifiers
@_implementationOnly import struct AVFoundation.AVError
@_implementationOnly import os

private func OSLog(category: String) -> os.OSLog {
#if DEBUG
    return OSLog(subsystem: "dev.uwapp.MediaPicker", category: category)
#else
    return .disabled
#endif
}

public extension View {
    /// Presents a system interface for allowing the user to import an existing
    /// media.
    ///
    /// In order for the interface to appear, `isPresented` must be `true`. When
    /// the operation is finished, `isPresented` will be set to `false` before
    /// `onCompletion` is called. If the user cancels the operation,
    /// `isPresented` will be set to `false` and `onCompletion` will not be
    /// called.
    ///
    /// - Note: Changing `allowedMediaTypes` while the media importer is
    ///   presented will have no immediate effect, however will apply the next
    ///   time it is presented.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the interface should be shown.
    ///   - allowedMediaTypes: The list of supported media types which can
    ///     be imported.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    ///   - result: A `Result` indicating whether the operation succeeded or
    ///     failed.
    func mediaImporter(
        isPresented: Binding<Bool>,
        allowedMediaTypes: MediaTypeOptions,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        self.mediaImporter(
            isPresented: isPresented,
            allowedMediaTypes: allowedMediaTypes,
            onCompletion: onCompletion,
            loadingOverlay: DefaultLoadingOverlay.init
        )
    }

    func mediaImporter<LoadingOverlay: View>(
        isPresented: Binding<Bool>,
        allowedMediaTypes: MediaTypeOptions,
        onCompletion: @escaping (Result<URL, Error>) -> Void,
        @ViewBuilder loadingOverlay: @escaping () -> LoadingOverlay
    ) -> some View {
        self.mediaImporter(
            isPresented: isPresented,
            allowedMediaTypes: allowedMediaTypes,
            allowsMultipleSelection: false,
            onCompletion: { result in
                onCompletion(result.map { $0.first! })
            },
            loadingOverlay: loadingOverlay
        )
    }
    
    /// Presents a system interface for allowing the user to import multiple
    /// medium.
    ///
    /// In order for the interface to appear, `isPresented` must be `true`. When
    /// the operation is finished, `isPresented` will be set to `false` before
    /// `onCompletion` is called. If the user cancels the operation,
    /// `isPresented` will be set to `false` and `onCompletion` will not be
    /// called.
    ///
    /// - Note: Changing `allowedMediaTypes` or `allowsMultipleSelection`
    ///   while the media importer is presented will have no immediate effect,
    ///   however will apply the next time it is presented.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to whether the interface should be shown.
    ///   - allowedMediaTypes: The list of supported media types which can
    ///     be imported.
    ///   - allowsMultipleSelection: Whether the importer allows the user to
    ///     select more than one media to import.
    ///   - onCompletion: A callback that will be invoked when the operation has
    ///     succeeded or failed.
    ///   - result: A `Result` indicating whether the operation succeeded or
    ///     failed.
    func mediaImporter(
        isPresented: Binding<Bool>,
        allowedMediaTypes: MediaTypeOptions,
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
        self.mediaImporter(
            isPresented: isPresented,
            allowedMediaTypes: allowedMediaTypes,
            allowsMultipleSelection: allowsMultipleSelection,
            onCompletion: onCompletion,
            loadingOverlay: DefaultLoadingOverlay.init
        )
    }
    
    func mediaImporter<LoadingOverlay: View>(
        isPresented: Binding<Bool>,
        allowedMediaTypes: MediaTypeOptions,
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void,
        @ViewBuilder loadingOverlay: @escaping () -> LoadingOverlay
    ) -> some View {
        self.mediaImporter(
            isPresented: isPresented,
            allowedMediaTypes: allowedMediaTypes,
            allowsMultipleSelection: allowsMultipleSelection,
            onCompletion: { (result: Result<[PHPickerResult], Error>) in
                switch result {
                case .success(let results):
                    Task {
                        do {
                            let images = try await imageURLs(from: results,
                                                             allowedContentTypes: allowedMediaTypes.typeIdentifiers)
                            isPresented.wrappedValue = false
                            onCompletion(.success(images))
                        } catch {
                            isPresented.wrappedValue = false
                            onCompletion(.failure(error))
                        }
                    }
                case .failure(let error):
                    onCompletion(.failure(error))
                }
            },
            loadingOverlay: loadingOverlay
        )
    }
}

fileprivate struct DefaultLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(.tertiarySystemBackground)
                .ignoresSafeArea()

            ProgressView("Importing Media...")
        }
    }
}

// Explore structured concurrency in Swift
// https://developer.apple.com/wwdc21/10134
fileprivate func imageURLs(from phPickerResults: [PHPickerResult],
                           allowedContentTypes: [UTType]) async throws -> [URL] {
    let log = OSLog(category: "imageURLs")
    let signpostID = OSSignpostID(log: log, object: phPickerResults as NSArray)
    return try await withThrowingTaskGroup(of: URL.self) { group in
        os_signpost(.begin, log: log, name: "imageURLs task group", signpostID: signpostID,
                    "Loading %d results", phPickerResults.count)
        var imageURLs = [URL]()
        imageURLs.reserveCapacity(phPickerResults.count)
        
        os_signpost(.begin, log: log, name: "imageURLs add task", signpostID: signpostID,
                    "Adding %d tasks", phPickerResults.count)
    pickerResultsLoop:
        for (index, result) in phPickerResults.enumerated() {
            let provider = result.itemProvider
            // TOOD: investigate should we instead use/consider
            // provider.registeredTypeIdentifiers
            for type in allowedContentTypes {
                if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                    os_signpost(.event, log: log, name: "imageURLs add task", signpostID: signpostID,
                                "Adding %d out of %d tasks: '%{public}@' of type %{public}@",
                                index + 1, phPickerResults.count, provider.suggestedName ?? "", type.identifier)
                    group.addTask {
                        try await provider.fileURL(for: type)
                    }
                    continue pickerResultsLoop
                }
            }
            throw AVError(.failedToLoadMediaData)
        }
        os_signpost(.end, log: log, name: "imageURLs add task", signpostID: signpostID)
        
        os_signpost(.begin, log: log, name: "imageURLs add url", signpostID: signpostID,
                    "Adding %d urls", phPickerResults.count)
        // Obtain results from the child tasks, sequentially.
        for try await imageURL in group {
            imageURLs.append(imageURL)
            os_signpost(.event, log: log, name: "imageURLs add url", signpostID: signpostID,
                        "Adding %d out of %d urls: %{public}@", imageURLs.count, phPickerResults.count, imageURL.path)
        }
        os_signpost(.end, log: log, name: "imageURLs add url", signpostID: signpostID)
        
        os_signpost(.end, log: log, name: "imageURLs task group", signpostID: signpostID)
        return imageURLs
    }
}

fileprivate extension NSItemProvider {
    // Meet async/await in Swift
    // https://developer.apple.com/wwdc21/10132/
    func fileURL(for type: UTType) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let log = OSLog(category: "fileURL")
            let signpostID = OSSignpostID(log: log, object: self)
            os_signpost(.begin, log: log, name: "fileURL continuation", signpostID: signpostID,
                        "%{public}@", suggestedName ?? "")
            
            os_signpost(.begin, log: log, name: "fileURL loadFileRepresentation", signpostID: signpostID,
                        "%{public}@", suggestedName ?? "")
            // https://developer.apple.com/forums/thread/652496
            loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                os_signpost(.end, log: log, name: "fileURL loadFileRepresentation", signpostID: signpostID)
                
                guard let src = url else {
                    os_signpost(.end, log: log, name: "fileURL continuation", signpostID: signpostID,
                                "errored, no src url")
                    return continuation.resume(throwing: error!)
                }
                do {
                    // Because the src/url will be deleted once we return,
                    // will copy the stored image to a different temp url.
                    let dst = FileManager.default.temporaryDirectory
                        .appendingPathComponent(src.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: dst.path) {
                        os_signpost(.begin, log: log, name: "fileURL copy", signpostID: signpostID,
                                    "fileURL copy from %@ to %@", src.path, dst.path)
                        try FileManager.default.copyItem(at: src, to: dst)
                        os_signpost(.end, log: log, name: "fileURL copy", signpostID: signpostID)
                    }
                    os_signpost(.end, log: log, name: "fileURL continuation", signpostID: signpostID,
                                "success")
                    continuation.resume(returning: dst)
                } catch {
                    os_signpost(.end, log: log, name: "fileURL continuation", signpostID: signpostID,
                                "errored, no dst url")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
