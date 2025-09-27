# Platform-Aware Local Storage Solution

## Problem

The original `LocalStorageService.dart` imported `dart:html` which is web-only, causing build failures on desktop platforms (Windows/Linux). This created the error:
```
LINK : fatal error LNK1104: cannot open file '..\extracted\firebase_cpp_sdk_windows\libs\windows\VS2019\MD\x64\Debug\firebase_firestore.lib'
```

## Solution

Implemented a platform-aware storage system using Dart's conditional imports feature.

### Architecture

```
lib/
├── platform_local_storage_service.dart  # Main service with conditional imports
├── storage_stub.dart                    # Fallback/stub implementation
├── storage_web.dart                     # Web implementation (dart:html)
├── storage_io.dart                      # Desktop implementation (dart:io)
└── LocalStorageService.dart             # Re-export for backward compatibility
```

### Conditional Import Pattern

```dart
import 'storage_stub.dart'
    if (dart.library.html) 'storage_web.dart'
    if (dart.library.io) 'storage_io.dart';
```

This pattern:
- Uses `storage_web.dart` when `dart:html` is available (web platform)
- Uses `storage_io.dart` when `dart:io` is available (desktop/mobile)
- Falls back to `storage_stub.dart` as default (throws errors)

### Platform Implementations

#### Web (`storage_web.dart`)
- Uses `window.localStorage` via `dart:html`
- Data stored in browser's localStorage
- Key: `'tra_receipts'`

#### Desktop (`storage_io.dart`) 
- Uses file system via `dart:io`
- Creates `TRA_Receipts/` directory in current working directory
- Saves to `TRA_Receipts/tra_receipts.json`
- Handles file creation, reading, writing, and deletion

### API

Both implementations provide the same interface:

```dart
class PlatformStorageImpl {
  static Future<void> saveData(String key, String data);
  static Future<String?> loadData(String key);
  static Future<void> removeData(String key);
  static Future<Map<String, dynamic>> getStorageInfo();
}
```

### Usage

```dart
// Same API across platforms
await PlatformLocalStorageService.saveReceipt(receiptData);
final receipts = await PlatformLocalStorageService.getReceipts();
final receipt = await PlatformLocalStorageService.getReceiptByCode('CODE123');
await PlatformLocalStorageService.deleteReceipt('CODE123');
await PlatformLocalStorageService.clearAllReceipts();
```

### Backward Compatibility

The original `LocalStorageService` class is preserved by re-exporting `PlatformLocalStorageService`:

```dart
// lib/LocalStorageService.dart
export 'platform_local_storage_service.dart';
```

### Migration Changes

Updated the following files to use async methods:
- `lib/ReceiptsListPageHybrid.dart` - Made `_loadLocalReceipts()` async
- `lib/AddReceiptPage.dart` - Updated import path
- `lib/ReceiptViewPage.dart` - Made storage calls async

### File Storage Location (Desktop)

- **Directory**: `TRA_Receipts/` in the application's working directory
- **File**: `tra_receipts.json`
- **Format**: JSON array of receipt objects
- **Permissions**: Created with default file permissions

### Error Handling

- Web: localStorage errors are caught and handled gracefully
- Desktop: File I/O errors fall back to current directory
- Both: Return empty arrays/null for missing data
- Errors logged to console for debugging

### Testing

The solution can be tested on both platforms:
- **Web**: Deploy to web server, check browser localStorage
- **Desktop**: Run on Windows/Linux/macOS, check `TRA_Receipts/` folder

### Benefits

1. **Cross-platform compatibility**: Works on web and desktop
2. **No external dependencies**: Uses only Dart core libraries  
3. **Backward compatibility**: Existing code continues to work
4. **Clean separation**: Platform-specific code isolated
5. **Error resilience**: Graceful fallbacks for all error conditions