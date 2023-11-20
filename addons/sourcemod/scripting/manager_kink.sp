#include <sourcemod>
#include <sdktools>
#include <morecolors>
#include <sdkhooks>

bool isKink;


public Plugin myinfo = {
    name        = "Kink Landmine Notifications",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

bool lateloaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateloaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("kinknotifs.phrases");

	if (lateloaded)
	{
		HookLandmines();
	}
}

void HookLandmines()
{
	int count = 0;
	char targetname[64];
	int e = -1;
	while ((e = FindEntityByClassname(e, "trigger_once")) != -1)
	{
		GetEntPropString(e, Prop_Data, "m_iName", targetname, sizeof(targetname));
		
		if (StrContains(targetname, "c4_bomb_") != -1)
		{
			HookSingleEntityOutput(e, "OnTrigger", OnLandmineTrigger);
			count++;
		}
	}

	PrintToServer("Hooked %d landmines", count);
}

public void OnMapStart()
{
	char mapName[PLATFORM_MAX_PATH];
	if (GetCurrentMap(mapName, sizeof(mapName)))
	{
		isKink = StrContains(mapName, "nmo_kink") != -1;
	}

	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	if (!isKink) {
		return;
	}

	HookLandmines();
}

void OnLandmineTrigger(const char[] output, int caller, int activator, float delay)
{
	if (IsPlayer(activator))
	{
		CPrintToChatAll("%t", "Triggered Landmine", activator);
	}
}

bool IsPlayer(int entity)
{
	return 0 < entity <= MaxClients;
}

