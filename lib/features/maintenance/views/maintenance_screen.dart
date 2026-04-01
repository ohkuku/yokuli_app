// The maintenance/维保 screen has been renamed to 看板 (Kanban).
// It now shows the full kanban board with LAN-synced operations.
// This file re-exports KanbanScreen as MaintenanceScreen for backward compatibility.

library maintenance_screen;

export '../../kanban/views/kanban_screen.dart' show KanbanScreen as MaintenanceScreen;
