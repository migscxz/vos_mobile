# Attendance Approval Grouping Task

## Steps to Complete

- [x] Add AttendanceApprovalGroup model to attendance_model.dart
- [x] Add approveSelectedAttendance method to attendance_repository.dart
- [x] Update attendance_view.dart to load all pending approvals, group by employee, and show grouped cards
- [x] Update attendance_sheet.dart to accept a list of approvals, display with checkboxes, handle selection, and approve selected items
- [x] Test the grouping, selection, and approval functionality

# Attendance Sheet Enhancements

## Steps to Complete

- [x] Add undertime_minutes and overtime_minutes displays in attendance_sheet.dart
- [x] Revise work_minutes logic: show "8h" if overtimeMinutes == 0, else show actual workMinutesLabel
- [x] Ensure late_minutes are displayed even if employee hasn't clocked out
- [x] Add loading spinner to "Approve Selected" button during processing
- [x] Test the UI changes and button behavior
