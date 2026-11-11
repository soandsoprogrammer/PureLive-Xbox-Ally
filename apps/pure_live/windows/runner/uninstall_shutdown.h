#ifndef RUNNER_UNINSTALL_SHUTDOWN_H_
#define RUNNER_UNINSTALL_SHUTDOWN_H_

#include <windows.h>

// Scoped to processes whose executable is the same installed file as ours.
UINT UninstallShutdownMessage();
int ShutdownInstalledInstances();

#endif  // RUNNER_UNINSTALL_SHUTDOWN_H_
