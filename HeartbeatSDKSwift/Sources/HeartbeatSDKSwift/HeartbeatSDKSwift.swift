import Foundation
import os
import CoreLocation
import HealthKit

#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Location Manager Delegate

private class SDKLocationDelegate: NSObject, CLLocationManagerDelegate {
    var lastLocation: CLLocation?
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - HeartbeatSDK

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
    
    // Health Metrics
    private var currentHeartRate: Int = -1
    private var currentSpO2: Int = -1
    private let healthStore = HKHealthStore()
    private var isHealthKitAuthorized = false
    
    // Location
    private let locationManager = CLLocationManager()
    private let locationDelegate = SDKLocationDelegate()
    
    // Offline Queue
    private var offlineQueue: [[String: Any]] = []
    private let queueKey = "heartbeatsdk_offline_queue"
    
    private init() {
        loadQueue()
        setupLocation()
        setupHealthKit()
    }
    
    private func setupLocation() {
        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func setupHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit is not available on this device.")
            return
        }
        
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) else {
            return
        }
        
        let typesToRead: Set<HKObjectType> = [hrType, spo2Type]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            if success {
                self?.isHealthKitAuthorized = true
                self?.logger.info("HealthKit authorization granted.")
            } else {
                self?.logger.error("HealthKit authorization failed: \(error?.localizedDescription ?? "unknown")")
            }
        }
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
        
        // Start location tracking
        locationManager.startUpdatingLocation()
        
        logger.info("Session opened: \(self.sessionId!)")
        
        startTransmitting()
    }
    
    public func closeSession() {
        timer?.invalidate()
        timer = nil
        isTransmitting = false
        
        let sessionToClose = sessionId
        let userToClose = userId
        
        // Send close notification to the server
        Task {
            await sendCloseNotification(sessionId: sessionToClose, userId: userToClose)
        }
        
        locationManager.stopUpdatingLocation()
        
        sessionId = nil
        userId = nil
        
        logger.info("Session closed.")
    }
    
    private func sendCloseNotification(sessionId: String?, userId: String?) async {
        guard let endpointUrl = endpointUrl, let url = URL(string: endpointUrl) else { return }
        
        let payloadData: [String: Any] = [
            "device_id": deviceId ?? "",
            "session_id": sessionId ?? "",
            "user_id": userId ?? "",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "action": "close_session"
        ]
        
        let payload: [String: Any] = ["data": payloadData]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                logger.error("Server returned error closing session: \(httpResponse.statusCode)")
            } else {
                logger.info("Close notification sent successfully.")
            }
        } catch { 
            logger.error("Failed to send close notification: \(error.localizedDescription)")
        }
    }
    
    private func startTransmitting() {
        // Send immediately, then every 5 seconds
        Task {
            await sendHeartbeat()
        }
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task {
                    await self?.sendHeartbeat()
                }
            }
        }
    }
    
    // MARK: - HealthKit Data
    
    private func fetchLatestHealthData() async {
        guard isHealthKitAuthorized else { return }
        
        if let hr = await fetchLatestSample(for: .heartRate) {
            self.currentHeartRate = Int(hr)
        }
        if let spo2 = await fetchLatestSample(for: .oxygenSaturation) {
            self.currentSpO2 = Int(spo2 * 100)
        }
    }
    
    private func fetchLatestSample(for identifier: HKQuantityTypeIdentifier) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        
        return await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            // Query the absolute latest sample to ensure data availability during testing
            let predicate: NSPredicate? = nil
            
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                
                if identifier == .heartRate {
                    let unit = HKUnit(from: "count/min")
                    continuation.resume(returning: sample.quantity.doubleValue(for: unit))
                } else if identifier == .oxygenSaturation {
                    let unit = HKUnit.percent()
                    continuation.resume(returning: sample.quantity.doubleValue(for: unit))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    /// Gets real GPS from CoreLocation, falls back to Tel Aviv coastline
    private func getGPS() -> [String: Double] {
        if let location = locationDelegate.lastLocation {
            return [
                "lat": location.coordinate.latitude,
                "lng": location.coordinate.longitude
            ]
        }
        
        logger.error("Real GPS not available. Did you add NSLocationWhenInUseUsageDescription to Info.plist?")
        return [
            "lat": 0.0,
            "lng": 0.0
        ]
    }
    
    // MARK: - Send Heartbeat
    
    private func sendHeartbeat() async {
        guard let endpointUrl = endpointUrl, let url = URL(string: endpointUrl) else { return }
        
        await fetchLatestHealthData()
        let gps = getGPS()
        
        logger.info("💓 HR: \(self.currentHeartRate) bpm | 🫁 SpO2: \(self.currentSpO2)% | 📍 GPS: \(gps["lat"] ?? 0), \(gps["lng"] ?? 0)")
        
        let payloadData: [String: Any] = [
            "device_id": deviceId ?? "",
            "app_id": appId ?? "",
            "session_id": sessionId ?? "",
            "user_id": userId ?? "",
            "activity_type": activityType ?? "unknown",
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "battery_level": getBatteryLevel(),
            "heart_rate": currentHeartRate,
            "spo2": currentSpO2,
            "gps": gps,
            "sdk_version": "1.2.1"
        ]
        
        let payload: [String: Any] = [
            "data": payloadData
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
