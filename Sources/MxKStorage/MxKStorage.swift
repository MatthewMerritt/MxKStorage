//
//  DiskStorage.swift
//  MxKGames
//
//  Created by Matthew Merritt on 12/31/20.
//
//  Based on: https://swiftwithmajid.com/2019/05/22/storing-codable-structs-on-the-disk/
//      by: https://github.com/mecid

import Foundation

public typealias StorageHandler<T> = (Result<T, Error>) -> Void

public protocol ReadableStorage {
    func fetchValue(for key: String) throws -> Data
    func fetchValue(for key: String, handler: @escaping StorageHandler<Data>)
}

public protocol WritableStorage {
    func save(value: Data, for key: String) throws
    func save(value: Data, for key: String, handler: @escaping StorageHandler<Data>)
}

public typealias Storage = ReadableStorage & WritableStorage

public enum StorageError: Error {
    case notFound
    case cantWrite(Error)
    case cantList(Error)
    case cantMove(Error)
    case cantRemove(Error)
}

public class DiskStorage {
    private let queue: DispatchQueue
    private let fileManager: FileManager
    private let path: URL

    public init(path: URL, queue: DispatchQueue = .init(label: "DiskCache.Queue"), fileManager: FileManager = FileManager.default) {
        self.path = path
        self.queue = queue
        self.fileManager = fileManager
    }
}

extension DiskStorage: WritableStorage {

    public func save(value: Data, for key: String) throws {
        let url = path.appendingPathComponent(key)

        do {
            try self.createFolders(in: url)
            try value.write(to: url, options: .atomic)
        } catch {
            throw StorageError.cantWrite(error)
        }
    }

    public func save(value: Data, for key: String, handler: @escaping StorageHandler<Data>) {

        queue.async {
            do {
                try self.save(value: value, for: key)
                handler(.success(value))
            } catch {
                handler(.failure(error))
            }
        }
    }
}

extension DiskStorage {

    private func createFolders(in url: URL) throws {
        let folderUrl = url.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: folderUrl.path) {
            try fileManager.createDirectory(
                at: folderUrl,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    public func listFiles(in url: URL) throws -> [URL]? {

        do {
            let directoryContents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])

            // Print the urls of the files contained in the documents directory
            return directoryContents
        } catch {
            throw StorageError.cantList(error)
        }

    }

    public func listFiles(url: URL, handler: @escaping StorageHandler<[URL]>) {

        queue.async {
            do {
                let directoryContents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])

                handler(.success(directoryContents))
            } catch {
                handler(.failure(error))
            }
        }
    }


    public func removeFiles(urls: [URL]) throws {

        do {
            for url in urls {
                try FileManager.default.removeItem(at: url)
            }

        } catch {
            throw StorageError.cantRemove(error)
        }

    }

    public func moveFile(from: URL, to: URL) throws {

        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            throw StorageError.cantMove(error)
        }

    }
}

extension DiskStorage: ReadableStorage {

    public func fetchValue(for key: String) throws -> Data {
        let url = path.appendingPathComponent(key)

        guard let data = fileManager.contents(atPath: url.path) else {
            throw StorageError.notFound
        }

        return data
    }

    public func fetchValue(for key: String, handler: @escaping StorageHandler<Data>) {

        queue.async {
            handler(Result { try self.fetchValue(for: key) })
        }
    }
}

public class CodableStorage {

    private let storage: DiskStorage
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(storage: DiskStorage, decoder: JSONDecoder = .init(), encoder: JSONEncoder = .init()) {
        self.storage = storage
        self.decoder = decoder
        self.encoder = encoder
    }

    public func fetch<T: Decodable>(for key: String) throws -> T {
        let data = try storage.fetchValue(for: key)
        return try decoder.decode(T.self, from: data)
    }

    public func save<T: Encodable>(_ value: T, for key: String) throws {
        let data = try encoder.encode(value)
        try storage.save(value: data, for: key)
    }
}
