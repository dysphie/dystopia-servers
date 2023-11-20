#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

bool isDangerSpot;

public Plugin myinfo = {
    name        = "Dangerspot Manager",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

public void OnMapStart()
{
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));
	isDangerSpot = StrContains(mapName, "nmo_dangerspot") != -1;

	TryPatchMap();
}

public void OnMapEnd()
{
	isDangerSpot = false;
}

public void OnPluginStart()
{
	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	if (isDangerSpot) {
		TryPatchMap();
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (isDangerSpot && StrEqual(classname, "info_player_nmrih"))
	{
		SDKHook(entity, SDKHook_Spawn, OnSpawnpointSpawned);
	}
}

Action OnSpawnpointSpawned(int spawnpoint)
{
	char buffer[32];
	GetEntPropString(spawnpoint, Prop_Data, "m_iName", buffer, sizeof(buffer));

	if (StrEqual(buffer, "spawn3"))
	{
		PrintToServer("Patched 1 spawnpoint");
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void TryPatchMap()
{
	RemoveByPrefix("info_player_nmrih", "spawn3");
}

void RemoveByPrefix(const char[] classname, const char[] partialName)
{
	char buffer[32];
	int e = -1;
	while ((e = FindEntityByClassname(e, classname)) != -1)
	{
		GetEntPropString(e, Prop_Data, "m_iName", buffer, sizeof(buffer));

		if (StrContains(buffer, partialName) == 0)
		{
			RemoveEntity(e);
			PrintToServer("Patched 1 spawnpoint");
		}
	}
}