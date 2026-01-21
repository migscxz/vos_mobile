# TODO: Add Pagination to Attendance View and Sheet

## attendance_view.dart

- [x] Change \_initialLimit from -1 to 20 for paginated initial load
- [x] Add \_totalPending variable to store total count from API
- [x] Modify \_reload to set \_totalPending = page.total
- [x] Update \_loadMore to merge new approvals into existing employee groups
- [x] Update total pending display to use \_totalPending

## attendance_sheet.dart

- [x] Change ListView to ListView.builder for virtualization

## Testing

- [x] Test changes for smooth loading and no duplicates
