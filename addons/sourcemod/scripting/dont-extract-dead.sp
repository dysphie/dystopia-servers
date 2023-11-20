#include <dhooks>
#include <sourcemod>

#define GAMEDATA_FILE "dont-extract-dead.games"

public Plugin myinfo =
{
	name        = "Don't Extract Dead Players",
	author      = "Dysphie",
	description = "",
	version     = "1.0.0",
	url         = ""
};

public void OnPluginStart()
{
	GameData gamedata = new GameData(GAMEDATA_FILE);
	if (!gamedata)
	{
		SetFailState("Failed to find " ... GAMEDATA_FILE);
	}

	DynamicDetour detour = DynamicDetour.FromConf(gamedata, "NMRiHGameState_ExtractPlayer");
	if (!detour)
		SetFailState("Failed to find signature NMRiHGameState_ExtractPlayer");
	detour.Enable(Hook_Pre, OnExtractPlayer);
	delete detour;
}

MRESReturn OnExtractPlayer(DHookParam params)
{
	if (params.IsNull(1))
	{
		return MRES_Supercede;
	}

	int entity = params.Get(1);
	if (IsPlayer(entity) && !IsPlayerAlive(entity))
	{
		// PrintToServer("Prevented extraction of %N as they're not alive", entity);
		return MRES_Supercede;
	}

	return MRES_Override;
}

bool IsPlayer(int entity)
{
	return 0 < entity <= MaxClients;
}