
#if defined _campaigns_included_
  #endinput
#endif
#define _campaigns_included_

#define MAX_CAMPAIGN_LEN PLATFORM_MAX_PATH + MAX_GAMEMODE_LEN + 1
#define MAX_GAMEMODE_LEN 32

native bool MM_IsValidMapAndMode(const char[] mapName, const char[] modeName);
native bool MM_GetCurrentMode(char[] modeName, int modeNameLen);
native bool MM_AreMapsAndModesLoaded();
forward void OnCampaignsLoaded();