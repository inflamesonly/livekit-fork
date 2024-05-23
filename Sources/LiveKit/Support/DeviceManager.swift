/*
 * Copyright 2024 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import AVFoundation

// Internal-only for now
class DeviceManager: Loggable {
    // MARK: - Public

    public static let shared = DeviceManager()

    public static func prepare() {
        // Instantiate shared instance
        _ = shared
    }

    // Async version, waits until inital device fetch is complete
    public func devices(types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]) async throws -> [AVCaptureDevice] {
        try await devicesCompleter.wait().filter { types.contains($0.deviceType) }
    }

    // Sync version
    public func devices(types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]) -> [AVCaptureDevice] {
        _state.devices.filter { types.contains($0.deviceType) }
    }

    private lazy var discoverySession: AVCaptureDevice.DiscoverySession = {
        var deviceTypes: [AVCaptureDevice.DeviceType]
        #if os(iOS)
        deviceTypes = [
            .builtInWideAngleCamera, // General purpose use
            .builtInTelephotoCamera,
            .builtInUltraWideCamera,
            .builtInTripleCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
        ]
        if #available(iOS 17.0, *) {
            deviceTypes.append(contentsOf: [
                .continuityCamera,
                .external,
            ])
        }
        #else
        deviceTypes = [
            .builtInWideAngleCamera,
        ]
        #endif

        return AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                mediaType: .video,
                                                position: .unspecified)
    }()

    private struct State {
        var devices: [AVCaptureDevice] = []
    }

    private let _state = StateSync(State())

    private let devicesCompleter = AsyncCompleter<[AVCaptureDevice]>(label: "devices", defaultTimeout: 10)

    private var _observation: NSKeyValueObservation?

    init() {
        log()

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            _observation = discoverySession.observe(\.devices, options: [.initial, .new]) { [weak self] _, value in
                guard let self else { return }
                let devices = value.newValue ?? []
                self.log("Devices: \(String(describing: devices))")
                self._state.mutate { $0.devices = devices }
                self.devicesCompleter.resume(returning: devices)
            }
        }
    }
}
