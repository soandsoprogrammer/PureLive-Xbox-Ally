; A compiler check that produces no installer and never modifies an installed app.
#ifndef ExpectedInnoVersion
  #error ExpectedInnoVersion is required
#endif
#if DecodeVer(Ver) != ExpectedInnoVersion
  #error Inno Setup does not match the pinned version
#endif

[Setup]
AppName=PureLive compiler check
AppVersion=0.0.0
CreateAppDir=no
Uninstallable=no
Output=no
