# Build script for verification-only app
Write-Host "Building TRA Receipt Verification App..." -ForegroundColor Green

# Copy main_verify.dart to main.dart temporarily
Copy-Item "lib\main_verify.dart" "lib\main_temp.dart"
Copy-Item "lib\main.dart" "lib\main_backup.dart"
Copy-Item "lib\main_verify.dart" "lib\main.dart"

try {
    # Build the web app
    flutter build web --release
    
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host "Verification app built to: build\web" -ForegroundColor Yellow
}
finally {
    # Restore original main.dart
    Copy-Item "lib\main_backup.dart" "lib\main.dart"
    Remove-Item "lib\main_backup.dart" -ErrorAction SilentlyContinue
    Remove-Item "lib\main_temp.dart" -ErrorAction SilentlyContinue
}

Write-Host "Ready to deploy to Firebase!" -ForegroundColor Green