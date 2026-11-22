# HomePage UI Refactoring Guide

## Current State
- `HomePage.dart`: **5,510 lines** (unmaintainable)
- Mixed business logic with UI rendering
- Slow hot reload, hard to test

## Refactored Target
- `HomePage.dart`: ~800 lines (orchestrator)
- `mobile_dashboard.dart`: ~400 lines
- `desktop_dashboard.dart`: ~350 lines
- `home_finance_card.dart`: ~300 lines
- `home_navigation_rail.dart`: ~250 lines
- Plus 5-6 smaller extracted widgets

## Before & After

### BEFORE (HomePage.dart lines 1884-2038)
```dart
Widget _buildMobileBusinessDashboard() {
  // 150+ lines of mobile UI mixed with state access
  final user = FirebaseAuth.instance.currentUser;
  final greetingName = ownerName.isNotEmpty ? ...;
  // Direct access to 50+ state variables
  return RefreshIndicator(
    onRefresh: _loadFinanceSummary,
    child: ListView(
      children: [
        // Inline 400 lines of UI...
      ],
    ),
  );
}
```

### AFTER (HomePage.dart)
```dart
Widget _buildDashboard() {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return MobileDashboard(
          ownerName: ownerName,
          financeIncome: financeIncome,
          onRefresh: _loadFinanceSummary,
          onAddTransaction: _openTransactionForm,
        );
      }
      return DesktopDashboard(...);
    },
  );
}
```

## Quick Wins (Start Here)

### 1. Fix Linter Issues (20 minutes)
- Add missing `{}` in if statements
- Replace `print()` → `debugPrint()`  
- Fix deprecated Color API usage

### 2. Extract MobileDashboard (1 hour)
Saves 400 lines from HomePage

### 3. Extract DesktopDashboard (1 hour)
Saves 350 lines from HomePage

### 4. Extract Finance Card (45 min)
Saves 300 lines from HomePage

**Result after 3 hours: 5510 → 2500 lines**
