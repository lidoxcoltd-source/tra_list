# HomePage Refactoring Plan

## Current State
- `HomePage.dart`: **5,510 lines** 
- Massive state mixed with UI
- Already has `home/models/` and `home/widgets/` but HomePage still huge

## Refactored Structure

```
lib/home/
├── controllers/
│   └── home_state_controller.dart     # State management only (no UI)
├── models/
│   └── home_models.dart                # ✓ Already exists
├── widgets/
│   ├── home_bottom_bar.dart            # ✓ Already exists
│   ├── home_debt_metrics.dart          # ✓ Already exists
│   ├── quick_actions_panel.dart        # ✓ Already exists
│   ├── business_wallet_preview.dart    # ✓ Already exists
│   ├── home_header.dart                # NEW: Extract _buildHeader + menu
│   ├── home_navigation_rail.dart       # NEW: Extract _buildNavigationRail
│   ├── desktop_dashboard.dart          # NEW: Extract desktop layout
│   ├── mobile_dashboard.dart           # NEW: Extract _buildMobileBusinessDashboard
│   ├── mobile_home_header.dart         # NEW: Extract _buildMobileHomeHeader
│   ├── mobile_balance_card.dart        # NEW: Extract _buildMobileBalanceCard
│   ├── mobile_finance_summary.dart     # NEW: Extract _buildMobileFinanceSummary
│   ├── home_finance_card.dart          # NEW: Extract _buildFinanceCard
│   ├── home_welcome_panel.dart         # NEW: Extract _buildWelcomePanel
│   └── home_shortcuts.dart             # NEW: Extract shortcut buttons
├── services/
│   └── home_data_service.dart          # NEW: Data loading logic
└── home_page.dart                      # Main orchestrator (~800 lines)
```

## Benefits
- Each widget file < 300 lines
- Testable components
- Clear responsibilities
- Easier code reviews
- Better hot reload performance

## Migration Strategy
1. Create service for data loading
2. Extract large widgets one by one
3. Update HomePage to use new widgets
4. Run tests after each extraction
5. Verify app still works

## Key Extractions Priority

### High Priority (Biggest Files)
1. Mobile Dashboard (400+ lines) → `mobile_dashboard.dart`
2. Desktop Dashboard (350+ lines) → `desktop_dashboard.dart`
3. Finance Card (300+ lines) → `home_finance_card.dart`
4. Navigation Rail (200+ lines) → `home_navigation_rail.dart`

### Medium Priority
5. Header & Menu (200+ lines) → `home_header.dart`
6. Welcome Panel (100+ lines) → `home_welcome_panel.dart`
7. Staff Summary (already extracted at 8KB ✓)

### Low Priority
8. Small utility widgets
9. Dialogs
10. Bottom sheets

## Implementation Notes

- Keep existing `_HomeLoadingView` in HomePage (it's clean)
- Preserve all GetX dependencies
- Don't change business logic
- Match existing naming conventions (`_AppColors`, `_Spacing`, etc.)
- Keep responsive breakpoints consistent (900px desktop, 600px tablet)
