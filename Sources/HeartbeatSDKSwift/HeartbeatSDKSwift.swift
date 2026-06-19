import Foundation
import os

#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

public class HeartbeatSDK {
    public static let shared = HeartbeatSDK()
    
    private let logger = Logger(subsystem: "com.heartbeatsdk", category: "HeartbeatSDK")
    
    // Config
    private var projectId: String?
    private var deviceId: String?
    private var appId: String?
    private var endpointUrl: String?
    
    // Session State
    private var isTransmitting = false
    private var sessionId: String?
    private var userId: String?
    private var activityType: String?
    private var timer: Timer?
    
    // Offline Queue
    private var offlineQueue: [[String: Any]] = []
    private let queueKey = "heartbeatsdk_offline_queue"
    
    private init() {
        loadQueue()
    }
    
    public func configure(projectId: String, deviceId: String, appId: String = Bundle.main.bundleIdentifier ?? "unknown") {
        self.projectId = projectId
        self.deviceId = deviceId
        self.appId = appId
        self.endpointUrl = "https://us-central1-\(projectId).cloudfunctions.net/onHeartbeatReceived"
        logger.info("SDK configured. Project: \(projectId), Device: \(deviceId)")
    }
    
    public func openSession(userId: String, activityType: String = "swimming") {
        guard projectId != nil else {
            logger.error("SDK not configured. Call configure() first.")
            return
        }
        
        if isTransmitting {
            logger.warning("Session already open. Closing previous session.")
            closeSession()
        }
        
        self.sessionId = UUID().uuidString
        self.userId = userId
        self.activityType = activityType
        self.isTransmitting = true
        
        logger.info("Session opened: \(self.sessionId!)")
        
        startTransmitting()
    }
    
    public func closeSession() {
        timer?.invalidate()
        timer = nil
        isTransmitting = false
        sessionId = nil
        userId = nil
        
        logger.info("Session closed.")
    }
    
    private func startTransmitting() {
        // Send immediately, then every 5 seconds
        sendHeartbeat()
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.sendHeartbeat()
            }
        }
    }
    
    private func sendHeartbeat() {
        guard let endpointUrl = endpointUrl, let url = URL(string: endpointUrl) else { return }
        
        let payload: [String: Any] = [
            "device_id": deviceId ?? "",
            "app_id": appId ?? "",
            "session_id": sessionId ?? "",
            "user_id": userId ?? "",
            "activity_type": activityType ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "battery_level": getBatteryLevel(),
            "gps": [
                "lat": 32.0853, // Mock GPS for now
                "lng": 34.7818
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            logger.error("Failed to serialize payload: \(error.localizedDescription)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Network error: \(error.localizedDescription). Queueing offline.")
                self.queueOffline(payload)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                self.logger.error("Server error: \(httpResponse.statusCode). Queueing offline.")
                self.queueOffline(payload)
                return
            }
            
            self.logger.info("Heartbeat sent successfully.")
            self.flushQueue()
        }
        
        task.resume()
    }
    
    private func getBatteryLevel() -> Int {
        #if os(watchOS)
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let level = WKInterfaceDevice.current().batteryLevel
        return level >= 0 ? Int(level * 100) : 100
        #elseif os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? Int(level * 100) : 100
        #else
        return 100
        #endif
    }
    
    private func queueOffline(_ payload: [String: Any]) {
        offlineQueue.append(payload)
        saveQueue()
        logger.warning("Heartbeat queued offline (queue size: \(self.offlineQueue.count))")
    }
    
    private func flushQueue() {
        guard !offlineQueue.isEmpty else { return }
        offlineQueue.removeAll()
        saveQueue()
    }
    
    private func saveQueue() {
        UserDefaults.standard.set(offlineQueue, forKey: queueKey)
    }
    
    private func loadQueue() {
        if let saved = UserDefaults.standard.array(forKey: queueKey) as? [[String: Any]] {
            offlineQueue = saved
        }
    }
}
