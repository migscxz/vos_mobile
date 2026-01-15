# UI Revision Plan for Overtime Views

## Objective

Revise overtime_view.dart and overtime_sheet.dart to match the professional UI style of stock_transfer and sales_order views. Focus on UI elements only; do not change app flow.

## Key UI Elements to Update

- AppBar: Use elevation 0, scrolledUnderElevation 0, backgroundColor cs.surface, centerTitle false, title as Column with main title and subtitle.
- Search/Filter Header: Container with surfaceContainerHighest background, rounded corners, improved TextField and filter button styling.
- Cards: Rounded corners (20 for main cards), subtle shadows, improved padding and layout.
- Status Badges/Pills: Consistent styling with background opacity and borders.
- Sheets: Improved border radius, shadows, drag handle, header layout, and bottom CTA styling.
- Colors and Typography: Match font weights, sizes, and color schemes.

## Steps

1. Update overtime_view.dart AppBar to professional style.
2. Revise search and filter header in overtime_view.dart.
3. Update \_OvertimeCard to match \_StockTransferCard style.
4. Update \_Pill, \_EmptyState, \_ErrorState in overtime_view.dart.
5. Update overtime_sheet.dart DraggableScrollableSheet container.
6. Revise header and drag handle in overtime_sheet.dart.
7. Update \_Card in overtime_sheet.dart to match professional style.
8. Improve bottom action buttons in overtime_sheet.dart.
9. Test and verify UI consistency.
