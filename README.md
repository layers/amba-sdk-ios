# Amba — Swift SDK

[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager/)

Amba is the agent-native backend-as-a-service for mobile and web apps. This package is the Swift SDK. Supports iOS 14+, macOS 12+, tvOS 14+, and watchOS 7+.

## Install via Swift Package Manager

```swift
// Package.swift
.package(url: "https://github.com/layers/amba-sdk-ios", from: "1.0.0")
```

Or in Xcode: **File → Add Package Dependencies → `https://github.com/layers/amba-sdk-ios`**.

## Configure + first call

```swift
import Amba

try await Amba.configure(apiKey: "amba_pk_…")

try await Amba.auth.signInAnonymously()
try await Amba.events.track("app_opened", properties: ["source": "deep_link"])
```

Read a typed collection with `Codable`:

```swift
struct Todo: Codable { let id: String; let title: String; let done: Bool }

let resp = try await Amba.collections.find("todos", as: Todo.self)
```

## PrivacyInfo

The `PrivacyInfo.xcprivacy` manifest in `Sources/Amba/` declares the SDK's data collection per Apple's PrivacyManifest spec. Your app's privacy report aggregates this with its own manifest.

## Docs

Full reference: <https://docs.amba.dev/sdk/ios>.

## License

MIT
