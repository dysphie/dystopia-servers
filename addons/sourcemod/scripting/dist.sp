#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <morecolors>

#define NMR_MAXPLAYERS 9

public Plugin myinfo =
{
	name = "Render Distance Limiter",
	author = "Dysphie",
	description = "",
	version = "",
	url = ""
};

int g_OriginalFog[NMR_MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };
int g_OverrideFog[NMR_MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };
float g_OverrideDist[NMR_MAXPLAYERS+1] = { -1.0, ... };

Database g_DB;

ConVar cvDisableDetour;

public void OnPluginStart()
{
	cvDisableDetour = CreateConVar("dist_disable_detour", "0");
	Database.Connect(OnDatabaseConnectResult, "storage-local");

	LoadTranslations("map-names.phrases");
	LoadTranslations("dist.phrases");
	
	SetupDetours();

	HookEvent("player_spawn", Event_PlayerSpawn);
	RegConsoleCmd("sm_dist", Cmd_Switch);
	RegAdminCmd("debug_dist", Cmd_DebugDist, ADMFLAG_ROOT);
}

Action Cmd_DebugDist(int client, int args)
{
	if (!IsDedicatedServer()) {
		client = 1;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			ReplyToCommand(client, "%N: %.f (controller: %d)", i, g_OverrideDist[i], 
				GetEntPropEnt(client, Prop_Data, "m_hCtrl")
			);
		}
	}

	return Plugin_Handled;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client)) {
		return;
	}
	
	FogControllerChanged(client);
}

public void OnClientDisconnect(int client)
{
	RemoveFogOverride(client, .restoreOriginal=false);

	g_OriginalFog[client] = INVALID_ENT_REFERENCE;
	g_OverrideFog[client] = INVALID_ENT_REFERENCE;
	g_OverrideDist[client] = -1.0;
}

void SetupDetours()
{
	GameData gamedata = new GameData("player-fog.games");
	if (!gamedata) {
		SetFailState("Missing gamedata file");
	}

	DynamicDetour detour = DynamicDetour.FromConf(gamedata, "CBasePlayer::InputSetFogController");
	if (!detour)
		SetFailState("Failed to find signature CBasePlayer::InputSetFogController");
	detour.Enable(Hook_Pre, Detour_InputSetFogController);
	delete detour;
}

MRESReturn Detour_InputSetFogController(int client, DHookParam params)
{
	if (cvDisableDetour.BoolValue) {
		return MRES_Ignored;
	}

	RequestFrame(Frame_FogControllerChanged, GetClientSerial(client));
	return MRES_Ignored;
}

void FogControllerChanged(int client)
{
	if (g_OverrideDist[client] != -1.0) {
		SetFogOverride(client, g_OverrideDist[client]);
	}
}

void Frame_FogControllerChanged(int clientSerial)
{
	int client = GetClientFromSerial(clientSerial);
	if (client && IsClientInGame(client))
	{
		FogControllerChanged(client);
	}
}

Action Cmd_Switch(int client, int args)
{
	if (!IsDedicatedServer()) {
		client = 1;
	}

	if (args < 1) 
	{
		CReplyToCommand(client, "%t", "Usage");
		return Plugin_Handled;
	}

	int clientID = GetSteamAccountID(client);
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));
	
	float wishRange = GetCmdArgFloat(1);

	if (wishRange <= 100.0) 
	{
		Database_ForgetMapFog(clientID, mapName);
		
		RemoveFogOverride(client, .restoreOriginal=true);

		TranslateIfExists(mapName, sizeof(mapName), client);
		CReplyToCommand(client, "%t", "Removed", mapName);

		return Plugin_Handled;
	}

	SetFogOverride(client, wishRange);
	//ReplyToCommand(client, "Overrode fog");
	
	Database_RememberMapFog(clientID, mapName, wishRange);

	TranslateIfExists(mapName, sizeof(mapName), client);
	CReplyToCommand(client, "%t", "Saved", wishRange, mapName);

	return Plugin_Handled;
}

public void OnClientAuthorized(int client, const char[] auth)
{
	int clientID = GetSteamAccountID(client);
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));

	char query[512];
	g_DB.Format(query, sizeof(query), 
		"SELECT range FROM custom_fog WHERE steam_id = %d AND map_name = '%s'",
		clientID, mapName);

	g_DB.Query(QueryResults_GetCustomFog, query, GetClientSerial(client));
}

void QueryResults_GetCustomFog(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResults_GetCustomFog: %s", error);
		return;
	}

	int client = GetClientFromSerial(clientSerial);
	if (!client) {
		return;
	}

	if (results.FetchRow())
	{
		float dist = results.FetchFloat(0);
		g_OverrideDist[client] = dist;

		if (IsClientInGame(client) && IsPlayerAlive(client)) {
			SetFogOverride(client, dist);
		}
	}
}

void TranslateIfExists(char[] buffer, int maxlen, int lang)
{
	if (TranslationPhraseExists(buffer))
	{
		Format(buffer, maxlen, "%T", buffer, lang);
	}
}

void SetFogOverride(int client, float dist)
{
	RemoveFogOverride(client, .restoreOriginal=false);

	if (IsPlayerAlive(client))
	{
		int newFog = -1;
		int currentFog = GetOriginalFog(client);
		if (currentFog != -1)
		{
			newFog = CloneFogController(currentFog, dist);
			g_OriginalFog[client] = EntIndexToEntRef(currentFog);
		}
		else
		{
			newFog = CreateFogController(dist);
		}
		
		SetFogController(client, newFog);
		g_OverrideFog[client] = EntIndexToEntRef(newFog);
	}
	
	g_OverrideDist[client] = dist;
}

void RemoveFogOverride(int client, bool restoreOriginal)
{
	if (IsValidEntity(g_OverrideFog[client])) {
		RemoveEntity(g_OverrideFog[client]);
	}
	
	if (restoreOriginal)
	{
		int originalFog = GetOriginalFog(client);
		if (originalFog != -1) {
			SetFogController(client, originalFog);
		}
	}
	
	g_OverrideDist[client] = -1.0;
}

int GetOriginalFog(int client)
{
	if (IsValidEntity(g_OverrideFog[client])) {
		return EntRefToEntIndex(g_OriginalFog[client]);
	}

	int fog = GetEntPropEnt(client, Prop_Data, "m_hCtrl");
	if (fog != -1 && GetEntProp(fog, Prop_Send, "m_fog.enable") == 0)
	{
		return -1;
	}

	return fog;
}

int CreateFogController(float wishRange)
{
	int fog = CreateEntityByName("env_fog_controller");
	SetEntPropFloat(fog, Prop_Send, "m_fog.farz", wishRange);
	DispatchSpawn(fog);

	return fog;
}

void SetFogController(int client, int fog)
{
	SetEntPropEnt(client, Prop_Data, "m_hCtrl", fog);
}

int CloneFogController(int fog, float wishRange)
{
	float pos[3];
	GetEntPropVector(fog, Prop_Data, "m_vecOrigin", pos);

	char targetname[128];
	GetEntPropString(fog, Prop_Data, "m_iName", targetname, sizeof(targetname));
	
	float maxRange = GetEntPropFloat(fog, Prop_Send, "m_fog.farz");
	bool fogEnable = GetEntProp(fog, Prop_Send, "m_fog.enable") != 0;
	int fogBlend = GetEntProp(fog, Prop_Send, "m_fog.blend");
	float fogDirPrimary[3];
	GetEntPropVector(fog, Prop_Send, "m_fog.dirPrimary", fogDirPrimary);
	int fogColorPrimary = GetEntProp(fog, Prop_Send, "m_fog.colorPrimary");
	int fogColorSecondary = GetEntProp(fog, Prop_Send, "m_fog.colorSecondary");
	float fogStart = GetEntPropFloat(fog, Prop_Send, "m_fog.start");
	float fogEnd = GetEntPropFloat(fog, Prop_Send, "m_fog.end");
	float fogMaxDensity = GetEntPropFloat(fog, Prop_Send, "m_fog.maxdensity");
	int fogColorPrimaryLerpTo = GetEntProp(fog, Prop_Send, "m_fog.colorPrimaryLerpTo");
	int fogColorSecondaryLerpTo = GetEntProp(fog, Prop_Send, "m_fog.colorSecondaryLerpTo");
	float fogStartLerpTo = GetEntPropFloat(fog, Prop_Send, "m_fog.startLerpTo");
	float fogEndLerpTo = GetEntPropFloat(fog, Prop_Send, "m_fog.endLerpTo");
	float fogLerpTime = GetEntPropFloat(fog, Prop_Send, "m_fog.lerptime");
	float fogDuration = GetEntPropFloat(fog, Prop_Send, "m_fog.duration");
	

	int newFog = CreateEntityByName("env_fog_controller");
	//DispatchKeyValue(newFog, "targetname", targetname); //fixme
	DispatchKeyValue(newFog, "targetname", "fogtest"); //fixme
	SetEntProp(newFog, Prop_Send, "m_fog.enable", fogEnable);
	SetEntProp(newFog, Prop_Send, "m_fog.blend", fogBlend);
	SetEntPropVector(newFog, Prop_Send, "m_fog.dirPrimary", fogDirPrimary);
	SetEntProp(newFog, Prop_Send, "m_fog.colorPrimary", fogColorPrimary);
	SetEntProp(newFog, Prop_Send, "m_fog.colorSecondary", fogColorSecondary);
	SetEntPropFloat(newFog, Prop_Send, "m_fog.start", fogStart);
	SetEntPropFloat(newFog, Prop_Send, "m_fog.end", fogEnd);
	SetEntPropFloat(newFog, Prop_Send, "m_fog.maxdensity", fogMaxDensity);
	SetEntProp(newFog, Prop_Send, "m_fog.colorPrimaryLerpTo", fogColorPrimaryLerpTo);
	SetEntProp(newFog, Prop_Send, "m_fog.colorSecondaryLerpTo", fogColorSecondaryLerpTo);
	SetEntPropFloat(newFog, Prop_Send, "m_fog.startLerpTo", fogStartLerpTo);
	SetEntPropFloat(newFog, Prop_Send, "m_fog.endLerpTo", fogEndLerpTo);
	SetEntPropFloat(newFog, Prop_Send, "m_fog.lerptime", fogLerpTime);
	SetEntPropFloat(newFog, Prop_Send, "m_fog.duration", fogDuration);

	//PrintToServer("wishrange is %f, maxrange is %f", wishRange, maxRange);
	if (maxRange > 1.0 && wishRange > maxRange) {
		wishRange = maxRange;
	}

	SetEntPropFloat(newFog, Prop_Send, "m_fog.farz", wishRange);
	//PrintToServer("set m_fog.farz to %f", wishRange);

	DispatchSpawn(newFog);

	TeleportEntity(newFog, pos);


	return newFog;
}

void Database_RememberMapFog(int clientID, const char[] mapName, float range)
{
	if (!clientID || !mapName[0]) {
		return;
	}

	char query[512];
	g_DB.Format(query, sizeof(query), 
		"INSERT OR REPLACE INTO custom_fog (steam_id, map_name, range) VALUES (%d, '%s', %.f)", 
		clientID, mapName, range);

	//PrintToServer(query);
	g_DB.Query(QueryResult_AddCustomFog, query);
}

void Database_ForgetMapFog(int clientID, const char[] mapName)
{
	if (!clientID || !mapName[0]) {
		return;
	}

	char query[512];
	g_DB.Format(query, sizeof(query), "DELETE from custom_fog WHERE steam_id = %d AND map_name = '%s'", clientID, mapName);
	//PrintToServer(query);
	g_DB.Query(QueryResult_RemoveCustomFog, query);
}

void QueryResult_RemoveCustomFog(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0]) {
		LogError("QueryResult_RemoveCustomFog: %s", error);
	}
}

void QueryResult_AddCustomFog(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0]) {
		LogError("QueryResult_AddCustomFog: %s", error);
	}
}



void OnDatabaseConnectResult(Database db, const char[] error, any data)
{
	if (!db) {
		SetFailState("Failed to connect to database. %s", error);
	}

	g_DB = db;

	char query[512];
	g_DB.Format(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS custom_fog ( " ...
		"steam_id INTEGER NOT NULL, " ...
		"map_name TEXT NOT NULL, " ...
		"range INTEGER NOT NULL, " ...
		"PRIMARY KEY (steam_id, map_name));"
	);
	
	g_DB.Query(QueryResult_CreateTables, query);
}

void QueryResult_CreateTables(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		SetFailState("Failed to create table: %s", error);
	}	
}