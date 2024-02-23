import ApplicationLibrary
import Foundation
import Libbox
import Library
import Network
import UIKit

class ApplicationDelegate: NSObject, UIApplicationDelegate {
    private var profileServer: ProfileServer?

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NSLog("Here I stand")
        LibboxSetup(FilePath.sharedDirectory.relativePath, FilePath.workingDirectory.relativePath, FilePath.cacheDirectory.relativePath, false)
        Task {
            await setup()
        }
        return true
    }

    private func setup() async {
        do {
            try await UIProfileUpdateTask.configure()
            NSLog("setup background task success")
        } catch {
            NSLog("setup background task error: \(error.localizedDescription)")
        }
        
        do {
            try await loadDefaultConfig()
            NSLog("load default config success")
        } catch {
            NSLog("load default config error: \(error.localizedDescription)")
        }
        
        if UIDevice.current.userInterfaceIdiom == .phone {
            await requestNetworkPermission()
        }
        await setupBackground()
    }

    private nonisolated func setupBackground() async {
        if #available(iOS 16.0, *) {
            do {
                let profileServer = try ProfileServer()
                profileServer.start()
                await MainActor.run {
                    self.profileServer = profileServer
                }
                NSLog("started profile server")
            } catch {
                NSLog("setup profile server error: \(error.localizedDescription)")
            }
        }
    }

    private nonisolated func requestNetworkPermission() async {
        if await SharedPreferences.networkPermissionRequested.get() {
            return
        }
        if !DeviceCensorship.isChinaDevice() {
            await SharedPreferences.networkPermissionRequested.set(true)
            return
        }
        URLSession.shared.dataTask(with: URL(string: "http://captive.apple.com")!) { _, response, _ in
            if let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    Task {
                        await SharedPreferences.networkPermissionRequested.set(true)
                    }
                }
            }
        }.resume()
    }
    
    private func loadDefaultConfig() async throws {
        guard let jsonData = loadJSONData(from: "DefaultConfig") else {
            NSLog("load json data error")
            return
        }
        
        // 数据写入本地
        let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
        try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
        let profileConfig = profileConfigDirectory.appendingPathComponent("config_0.json")
        try jsonData.write(to: profileConfig)
        
        // 初始化profile对象
        let profile = Profile(
            id: 1,
            name: "DefaultProfile",
            type: .local,
            path: profileConfig.relativePath,
            remoteURL: "",
            autoUpdate: true,
            autoUpdateInterval: 60,
            lastUpdated: nil
        )
        
        // 数据存在数据库则更新，不存在则写入
        if let profile = try await ProfileManager.get(1) {
            try await ProfileManager.update(profile)
            NSLog("update profile success")
        } else {
            try await ProfileManager.create(profile)
            NSLog("create profile success")
        }
    }
    
    private func loadJSONData(from fileName: String) -> Data? {
        if let path = Bundle.main.path(forResource: fileName, ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                return data
            } catch {
                print("Error reading JSON file: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
}
