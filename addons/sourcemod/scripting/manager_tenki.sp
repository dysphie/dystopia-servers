#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo = {
    name        = "Tenki Manager",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

bool g_IsTenki = false;
ConVar cvStage;

public void OnPluginStart()
{
	cvStage = CreateConVar("sm_tenki_stage", "1");
	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	switch (cvStage.IntValue)
	{
		case 1:
		{
			InputLogicCase("stage_case", 1);
		}
		case 2:
		{
			InputLogicCase("stage_case", 4);
		}
		case 3:
		{
			InputLogicCase("stage_case", 5);
		}
	}
}

public void OnMapStart()
{
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));
	g_IsTenki = StrContains(mapName, "nmo_tenkinoko_welkin") == 0;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_IsTenki || !StrEqual(classname, "func_button")) {
		return;
	}

	SDKHook(entity, SDKHook_SpawnPost, OnButtonSpawned);
}

void OnButtonSpawned(int button)
{
	char targetname[32];
	GetEntityTargetname(button, targetname, sizeof(targetname));

	if (StrContains(targetname, "item_") != 0) {
		return;
	}

	int machete = GetPowerUpMachete(button);
	if (machete != -1)
	{
		HookSingleEntityOutput(button, "OnPressed", OnPowerUpButtonPressed);
		PrintToServer("Patched powerup '%s'", targetname);
	}
}

Action OnPowerUpButtonPressed(const char[] output, int caller, int activator, float delay)
{
	if (!IsPlayer(activator) || !CouldUsePowerUp(activator, caller)) 
	{
		// PrintToServer("Preventing accidental activation by %N", activator);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

bool IsPlayer(int entity)
{
	return 0 < entity <= MaxClients;
}

bool CouldUsePowerUp(int client, int button)
{
	int machete = GetPowerUpMachete(button);
	return machete != -1 && GetEntityOwner(machete) == client;
}

int GetEntityOwner(int entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hOwner");
}

int GetPowerUpMachete(int button)
{
	int moveParent = GetEntPropEnt(button, Prop_Data, "m_hMoveParent");
	if (IsValidEdict(moveParent))
	{
		char classname[32];
		GetEntityClassname(moveParent, classname, sizeof(classname));

		if (StrEqual(classname, "me_machete")) {
			return moveParent;
		}
	}

	return -1;
}

void InputLogicCase(const char[] name, int value)
{	
	int e = INVALID_ENT_REFERENCE;
	while ((e = FindEntityByClassname(e, "logic_case")) != -1)
	{
		char targetname[32];
		GetEntityTargetname(e, targetname, sizeof(targetname));

		if (StrEqual(targetname, name))
		{
			PrintToServer("Found logic case, setting it to %d", value);
			SetVariantInt(value);
			AcceptEntityInput(e, "InValue", e, e);
			break;
		}
	}
}

int GetEntityTargetname(int entity, char[] name, int maxlen)
{
	return GetEntPropString(entity, Prop_Data, "m_iName", name, maxlen);
}