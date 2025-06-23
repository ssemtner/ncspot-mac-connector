//
//  spotApp.swift
//  spot
//
//  Created by Scott Semtner on 6/23/25.
//

import SwiftUI
import Foundation
import MediaPlayer

func registerMediaCommands(getState: @escaping () -> PlaybackState?, exec: @escaping (String) -> Void) {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    
    commandCenter.playCommand.addTarget { event in
        print("macOS Play command received")
        let state = getState()
        guard state != nil else {
            return .deviceNotFound
        }
        switch state!.mode {
        case .playing(_):
            break
        case .paused(_):
            exec("playpause")
        case .stopped:
            exec("play")
        }
        return .success
    }
    
    commandCenter.pauseCommand.addTarget { event in
        print("macOS Pause command received")
        let state = getState()
        guard state != nil else {
            return .deviceNotFound
        }
        switch state!.mode {
        case .playing(_):
            exec("playpause")
        case .paused(_):
            break
        case .stopped:
            break
        }
        return .success
    }
    
    commandCenter.togglePlayPauseCommand.addTarget { event in
        print("macOS Toggle Play/Pause command received")
        exec("playpause")
        return .success
    }
    
    commandCenter.nextTrackCommand.addTarget { event in
        print("macOS Next Track command received")
        exec("next")
        return .success
    }
    
    commandCenter.previousTrackCommand.addTarget { event in
        print("macOS Previous Track command received")
        exec("previous")
        return .success
    }
}

func updateNowPlaying(state: PlaybackState) {
    let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    var playbackRate = 0;
    if case .playing(_) = state.mode {
        playbackRate = 1;
    }
    nowPlayingInfoCenter.nowPlayingInfo = [
        MPMediaItemPropertyTitle: state.playable?.title ?? "unknown",
        MPMediaItemPropertyArtist: state.playable?.artists?.joined(separator: ", ") ?? "unknown",
        MPMediaItemPropertyPlaybackDuration: state.playable?.duration ?? 0,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
        MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
    ]
    nowPlayingInfoCenter.playbackState = switch state.mode {
    case .playing(_):
            .playing
    case .paused(_):
            .paused
    case .stopped:
            .stopped
    }
    print("Updated Now Playing Info Center (macOS).")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var socketClient: SocketClient!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        socketClient = SocketClient()
        socketClient.connect()
        registerMediaCommands(
            getState: {
                self.socketClient.state
            },
            exec: socketClient.sendCommand
        )
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        socketClient.disconnect()
    }
}

class SocketClient: ObservableObject {
    @Published var state: PlaybackState?
    
    private var socket: Int32?
    private var readSource: DispatchSourceRead?
    
    func connect() {
        guard socket == nil else {
            print("socket was already connecting")
            return
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            print("attempting to connect")
            
            self.socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            if self.socket ?? -1 < 0 {
                print("failed to create socket \(String(cString: strerror(errno)))")
                return
            }
            
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let path = getFile()
            print(path)
            path.withCString({ cstr in
                withUnsafeMutablePointer(to: &address.sun_path.0) { dest in
                    _ = strcpy(dest, cstr)
                }
            })
            
            if Darwin.connect(self.socket!, withUnsafePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }), socklen_t(MemoryLayout<sockaddr_un>.size)) == -1 {
                print("error connecting \(String(cString: strerror(errno)))")
                self.closeSocket(self.socket)
                return
            }
            
            print("connected")
            
            self.readSource = DispatchSource.makeReadSource(fileDescriptor: self.socket!, queue: DispatchQueue.global(qos: .background))
            
            self.readSource?.setEventHandler { [weak self] in
                self?.handleRead()
            }
            
            self.readSource?.setCancelHandler { [weak self] in
                print("read source cancelled")
                self?.closeSocket(self?.socket)
                self?.socket = nil
            }
            
            self.readSource?.resume()
        }
    }
    
    func disconnect() {
        readSource?.cancel()
        readSource = nil
        
        closeSocket(socket)
        
        DispatchQueue.main.async {
            self.state = nil        }
        
        print("disconnected")
    }
    
    func sendCommand(command: String) {
        let message = command + "\n"
        if let data = message.data(using: .utf8) {
            data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                if let baseAddress = pointer.baseAddress {
                    let bytesSent = Darwin.send(socket!, baseAddress, data.count, 0)
                    if bytesSent == -1 {
                        print("Error sending message to socket - \(String(cString: strerror(errno)))")
                    } else {
                        print("Sent \(bytesSent) bytes: \(message)")
                    }
                }
            }
        }
    }
    
    private func getFile() -> String {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        
        task.executableURL = URL(fileURLWithPath: "/run/current-system/sw/bin/ncspot")
        task.arguments = ["info"]
        
        do {
            try task.run()
        }
        catch {
            print("failed to run ncspot")
            return ""
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        
        let parts = output?.components(separatedBy: .whitespacesAndNewlines)
        guard parts != nil else {
            print("parts is nil")
            return ""
        }
        let path = parts![parts!.endIndex - 2]
        
        return URL(fileURLWithPath: path).appendingPathComponent("ncspot.sock").path()
    }
    
    private func handleRead() {
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        let bytesRead = recv(socket!, &buffer, bufferSize, 0)
        
        if bytesRead < 0 {
            print("error reading \(String(cString: strerror(errno)))")
            readSource?.cancel()
            return
        } else if bytesRead == 0 {
            print("server disconnected")
            readSource?.cancel()
            return
        } else {
            let data = Data(bytes: buffer, count: bytesRead)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            do {
                let playbackState = try decoder.decode(PlaybackState.self, from: data)
                
                DispatchQueue.main.async {
                    self.state = playbackState
                }
                
                updateNowPlaying(state: playbackState)
            } catch {
                print("JSON parsing error: \(error)")
            }
        }
    }
    
    private func closeSocket(_ fd: Int32?) {
        if let fd = fd {
            if Darwin.close(fd) < 0 {
                print("error closing socket \(String(cString: strerror(errno)))")
            }
            
            print("closed socket")
        }
    }
}

@main
struct spotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("spot", systemImage: "music.note") {
            Button("Reconnect") {
                appDelegate.socketClient.disconnect()
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
                    appDelegate.socketClient.connect()
                }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
