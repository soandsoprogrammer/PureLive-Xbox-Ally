# PureLive window_manager compatibility patch

Upstream: https://pub.dev/packages/window_manager/versions/0.5.2 (leanflutter/window_manager, MIT).
Published archive SHA-256: 05c231fd7b23d2380f14c5cc10b7b93d60d4fa4a2fb4e0f032de27e44b5560e9.

Only the screen_retriever constraint and display-position utility are migrated to 0.3.0. Native window code is unchanged. Snapshot and release native display handles, keep logical pixel coordinates, and use the work area when positioning windows. The local app separately migrates display reads and persisted mini-window identity. See Z01.3 for validation.
