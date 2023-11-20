
#if defined _mapnmodes_included_
  #endinput
#endif
#define _mapnmodes_included_

#define MAX_GAMEMODE_LEN 32

native ArrayList MM_GetMapModes(const char[] mapName);
native ArrayList MM_GetMaps(const char[] mapNameFilter = "");
native bool MM_SetNextMapAndMode(const char[] mapName, const char[] modeName);
native bool MM_IsValidMapAndMode(const char[] mapName, const char[] modeName);
native void MM_ChangeMapAndMode();
native bool MM_GetRandomMapAndMode(char mapName[PLATFORM_MAX_PATH], char modeName[MAX_GAMEMODE_LEN]);
native bool MM_GetCurrentMode(char[] modeName, int modeNameLen);
native bool MM_AreMapsAndModesLoaded();
forward void MM_OnMapsAndModesLoaded();