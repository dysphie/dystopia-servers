#include <maps-n-modes>

GlobalForward g_OnMapsAndModesLoaded;

ArrayList g_MapList; // {"map1", "map2", map3"}
StringMap g_Gamemodes; // "gamemode1": { {"cvar1", "value1"}, {"cvar2", "value2"} }
StringMap g_Maps; // "map1": { "gamemode1", "gamemode2" }

public Plugin myinfo = {
    name        = "Database Campaigns",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};


enum struct GamemodeCvar
{
	char name[64];
	char value[64];
	char originalValue[64];
}

char g_PendingMode[32];
char g_ActiveGamemode[32];
char g_PendingMap[PLATFORM_MAX_PATH];
bool g_ConfigsLoaded;

public void OnPluginStart()
{
	g_Maps = new StringMap();
	g_Gamemodes = new StringMap();
	g_MapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	RegisterGamemodes();
	RegisterMaps();

	g_ConfigsLoaded = true;

	Call_StartForward(g_OnMapsAndModesLoaded);
	Call_Finish();

	RegAdminCmd("dump_gamemodes", Cmd_DumpGamemodes, ADMFLAG_ROOT);
	RegAdminCmd("sm_reload_campaigns", Cmd_ReloadCampaigns, ADMFLAG_ROOT);
}

Action Cmd_ReloadCampaigns(int client, int args)
{
	RegisterGamemodes();
	RegisterMaps();

	ReplyToCommand(client, "Reloaded gamemodes and maps");
	return Plugin_Handled;
}

Action Cmd_DumpGamemodes(int client, int args)
{
	StringMapSnapshot snap = g_Gamemodes.Snapshot();

	for (int i = 0; i < snap.Length; i++)
	{
		char mode[MAX_GAMEMODE_LEN];
		snap.GetKey(i, mode, sizeof(mode));
		ReplyToCommand(client, "Gamemode: %s", mode);
	}

	delete snap;
	return Plugin_Handled;
}

// void RegisterMapNames()
// {
// 	char file[PLATFORM_MAX_PATH];
// 	BuildPath(Path_SM, file, sizeof(file), "configs/map_names.cfg");

// 	File f = OpenFile(file, "r");
// 	if (!f) {
// 		SetFailState("Faile to load map_names.cfg");
// 	}

// 	char line[1024];

// 	while (f.ReadLine(line, sizeof(line)))
// 	{
// 		TrimString(line);
// 		int nameStartAt = SplitString(line, " ", file, sizeof(file));
// 		PrintToServer("Got '%s' for '%s'", line[nameStartAt], line);
// 	}
// }

void RegisterGamemodes()
{
	g_Gamemodes.Clear();

	char basePath[PLATFORM_MAX_PATH];
	char iterBuffer[PLATFORM_MAX_PATH]; FileType fileType;
	BuildPath(Path_SM, basePath, sizeof(basePath), "configs/gamemodes");

	DirectoryListing ls = OpenDirectory(basePath);
	if (!ls) {
		SetFailState("Failed to open %s", basePath);
	}

	while (ls.GetNext(iterBuffer, sizeof(iterBuffer), fileType)) 
	{
		if (fileType != FileType_File) {
			continue;
		}

		int baseLen = strlen(iterBuffer) - 4;
		if (baseLen < 0) {
			PrintToServer("Ignoring %s", iterBuffer);
			continue;
		}

		if (strcmp(iterBuffer[baseLen], ".txt") && 
			strcmp(iterBuffer[baseLen], ".cfg") && 
			strcmp(iterBuffer[baseLen], ".ini")) {
			continue;
		}

		char[] gamemodeName = new char[baseLen + 1];
		strcopy(gamemodeName, baseLen + 1, iterBuffer);
		StrLower(gamemodeName);

		Format(iterBuffer, sizeof(iterBuffer), "%s/%s", basePath, iterBuffer);

		File f = OpenFile(iterBuffer, "r");
		if (!f) 
		{
			LogError("Couldn't open %s", iterBuffer);
			continue;
		}

		ArrayList cvars = new ArrayList(sizeof(GamemodeCvar));

		char line[255];
		while (f.ReadLine(line, sizeof(line)))
		{
			TrimString(line);

			// TODO: Remove ExplodeString and write to struct directly with Regex
			char cvarData[2][64];
			ExplodeString(line, " ", cvarData, sizeof(cvarData), sizeof(cvarData[]));

			GamemodeCvar cvar;
			strcopy(cvar.name, sizeof(cvar.name), cvarData[0]);
			strcopy(cvar.value, sizeof(cvar.value), cvarData[1]);

			cvars.PushArray(cvar);

			// PrintToServer("Got line: %s %s", cvarData[0], cvarData[1]);
		}

		g_Gamemodes.SetValue(gamemodeName, cvars);
		
		PrintToServer("Registered gamemode \"%s\" with %d cvars", gamemodeName, cvars.Length);

		delete f;
	}

	delete ls;
}

void RegisterMaps()
{
	g_Maps.Clear();

	char buffer[1024];
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/campaigns.cfg");

	File f = OpenFile(buffer, "r");
	if (!f) {
		SetFailState("Failed to load maps.cfg");
	}

	char variables[2][256];
	while (f.ReadLine(buffer, sizeof(buffer)))
	{
		TrimString(buffer);
		ExplodeString(buffer, " ", variables, sizeof(variables), sizeof(variables[]));
		StrLower(variables[0]);
		StrLower(variables[1]);

		if (!IsMapValid(variables[0])) 
		{
			PrintToServer("LogMessage: Ignoring '%s': map not in filesystem", buffer);
			continue;
		}

		if (!GamemodeExists(variables[1]))
		{
			PrintToServer("LogMessage: Ignoring '%s': gamemode '%s' doesn't exist", buffer, variables[1]);
			continue;
		}

		ArrayList gamemodes;
		if (!g_Maps.GetValue(variables[0], gamemodes)) 
		{
			// This is the first time seeing this map name, push it to map list
			// and initialize gamemodes array
			g_MapList.PushString(variables[0])
			gamemodes = new ArrayList(ByteCountToCells(MAX_GAMEMODE_LEN));
		}

		gamemodes.PushString(variables[1]);
		g_Maps.SetValue(variables[0], gamemodes);
		PrintToServer("Registered map \"%s %s\"", variables[0], variables[1]);
	}

	delete f;
}

bool ChangeMapAndMode()
{
	if (!g_PendingMap[0] || !g_PendingMode[0]) {
		GetRandomMapAndMode(g_PendingMap, sizeof(g_PendingMap), g_PendingMode, sizeof(g_PendingMode))
	}

	ServerCommand("changelevel %s", g_PendingMap);
	return true;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_OnMapsAndModesLoaded = new GlobalForward("MM_OnMapsAndModesLoaded", ET_Ignore);

	CreateNative("MM_GetMaps", Native_GetMaps);
	CreateNative("MM_GetMapModes", Native_GetMapModes);
	CreateNative("MM_AreMapsAndModesLoaded", Native_AreMapsAndModesLoaded);
	CreateNative("MM_SetNextMapAndMode", Native_SetNextMapAndMode);
	CreateNative("MM_IsValidMapAndMode", Native_IsValidMapAndMode);
	CreateNative("MM_ChangeMapAndMode", Native_ChangeMapAndMode);
	CreateNative("MM_GetRandomMapAndMode", Native_GetRandomMapAndMode);
	CreateNative("MM_GetCurrentMode", Native_GetCurrentMode);
	return APLRes_Success;
}

any Native_GetCurrentMode(Handle plugin, int numParams)
{
	if (!g_ActiveGamemode[0]) {
		return false;
	}

	SetNativeString(1, g_ActiveGamemode[0], GetNativeCell(2));
	return true;
}

any Native_ChangeMapAndMode(Handle plugin, int numParams)
{
	ChangeMapAndMode();
	return 0;
}


any Native_AreMapsAndModesLoaded(Handle plugin, int numParams)
{
	return g_ConfigsLoaded;
}

any Native_IsValidMapAndMode(Handle plugin, int numParams)
{
	char mapFileName[PLATFORM_MAX_PATH];
	GetNativeString(1, mapFileName, sizeof(mapFileName));

	ArrayList gamemodes;
	if (!g_Maps.GetValue(mapFileName, gamemodes)) {
		return false;
	}

	char gamemodeName[32];
	GetNativeString(2, gamemodeName, sizeof(gamemodeName));
	int gamemodeIdx = gamemodes.FindString(gamemodeName);
	return gamemodeIdx != -1;
}

any Native_SetNextMapAndMode(Handle plugin, int numParams)
{
	PrintToServer("MM_SetNextMapAndMode 1");
	char mapFileName[PLATFORM_MAX_PATH];
	GetNativeString(1, mapFileName, sizeof(mapFileName));

	ArrayList gamemodes;
	if (!g_Maps.GetValue(mapFileName, gamemodes)) {
		return false;
	}

	PrintToServer("MM_SetNextMapAndMode 2");
	char gamemodeName[32];
	GetNativeString(2, gamemodeName, sizeof(gamemodeName));
	int gamemodeIdx = gamemodes.FindString(gamemodeName);

	if (gamemodeIdx == -1) {
		return false;
	}

	PrintToServer("MM_SetNextMapAndMode 3");
	strcopy(g_PendingMap, sizeof(mapFileName), mapFileName);
	strcopy(g_PendingMode, sizeof(g_PendingMode), gamemodeName);
	return true;
}

any Native_GetMaps(Handle plugin, int numParams)
{
	char filter[PLATFORM_MAX_PATH];
	GetNativeString(1, filter, sizeof(filter));

	if (!filter[0]) {
		return g_MapList.Clone();
	}

	ArrayList filtered = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	int maxMaps = g_MapList.Length;

	char mapName[PLATFORM_MAX_PATH];
	
	for (int i = 0; i < maxMaps; i++)
	{
		g_MapList.GetString(i, mapName, sizeof(mapName));

		if (!filter[0] || StrContains(mapName, filter, false) != -1)
		{
			filtered.PushString(mapName);
		}
	}

	ArrayList filteredClone = filtered.Clone();
	delete filtered;
	return filteredClone;
}

ArrayList GetMapGamemodes(const char[] mapName)
{
	ArrayList gamemodes;
	if (!g_Maps.GetValue(mapName, gamemodes)) {
		return new ArrayList(ByteCountToCells(MAX_GAMEMODE_LEN));
	}

	return gamemodes;
}

any Native_GetMapModes(Handle plugin, int numParams)
{
	char mapName[PLATFORM_MAX_PATH];
	GetNativeString(1, mapName, sizeof(mapName));

	ArrayList gamemodes;
	if (!g_Maps.GetValue(mapName, gamemodes)) 
	{
		gamemodes = new ArrayList(ByteCountToCells(MAX_GAMEMODE_LEN));
		ArrayList gamemodesClone = gamemodes.Clone();
		delete gamemodes;
		return gamemodesClone;
	}

	return gamemodes;
}

// TODO: Maybe make it into an iterator, idk
// any Native_Native_GetGamemodeCvars(Handle plugin, int numParams)
// {
// 
// }

public void OnMapEnd()
{
	UnloadCurrentGamemode();
}

public void OnConfigsExecuted()
{
	if (!g_PendingMode[0]) 
	{
		// If we don't have a pending gamemode, pick one at random

		char mapName[PLATFORM_MAX_PATH];
		GetCurrentMap(mapName, sizeof(mapName));
		PrintToServer("Picking random gamemode for %s", mapName);

		ArrayList modes = MM_GetMapModes(mapName);
		if (modes.Length <= 0) 
		{
			LogMessage("No gamemodes available for %s. Extraction stats might not work", mapName);
			return;
		}

		int rnd = GetRandomInt(0, modes.Length - 1);
		modes.GetString(rnd, g_PendingMode, sizeof(g_PendingMode));
		delete modes;
	}

	LoadGamemode(g_PendingMode);
	g_PendingMode[0] = 0;
}

int Native_GetRandomMapAndMode(Handle plugin, int numParams)
{
	char mapName[PLATFORM_MAX_PATH];
	char modeName[64];

	if (!GetRandomMapAndMode(mapName, sizeof(mapName), modeName, sizeof(modeName)))	{
		return false;
	}

	SetNativeString(1, mapName, PLATFORM_MAX_PATH);
	SetNativeString(2, modeName, MAX_GAMEMODE_LEN);
	return true;
}

bool GetRandomMapAndMode(char[] mapName, int mapNameLen, char[] modeName, int modeNameLen)
{
	int maxMaps = g_MapList.Length;
	if (maxMaps <= 0) {
		return false;
	}

	// First pick a random map
	int mapIdx = GetRandomInt(0, maxMaps - 1);
	g_MapList.GetString(mapIdx, mapName, mapNameLen);

	ArrayList gamemodes = GetMapGamemodes(mapName);
	int maxGamemodes = gamemodes.Length;
	if (maxGamemodes <= 0) {
		return false;
	}

	int gamemodeIdx = GetRandomInt(0, maxGamemodes - 1);
	gamemodes.GetString(gamemodeIdx, modeName, modeNameLen);
	return true;
}


bool GamemodeExists(const char[] modeName)
{
	return g_Gamemodes.ContainsKey(modeName);
}

void StrLower(char[] str)
{
	for (int i = 0; str[i]; i++)
	{
		str[i] = CharToLower(str[i]);
	}
}

void UnloadCurrentGamemode()
{
	if (!g_ActiveGamemode[0]) {
		return;
	}

	PrintToServer("Unloading gamemode '%s'", g_ActiveGamemode);

	ArrayList cvars;
	PrintToServer("GetValue %s", g_ActiveGamemode);
	if (!g_Gamemodes.GetValue(g_ActiveGamemode, cvars)) {
		return;
	}

	int maxCvars = cvars.Length;
	GamemodeCvar cvarData;
	ConVar cvar;

	for (int i = 0; i < maxCvars; i++)
	{
		cvars.GetArray(i, cvarData);

		cvar = FindConVar(cvarData.name);
		if (cvar) {
			cvar.SetString(cvarData.originalValue);
		}
	}
}

void LoadGamemode(const char[] modeName)
{
	UnloadCurrentGamemode();

	if (!modeName[0]) {
		return;
	}

	ArrayList cvars;
	if (!g_Gamemodes.GetValue(g_PendingMode, cvars)) 
	{
		return;
	}

	int maxCvars = cvars.Length;
	GamemodeCvar cvarData;

	ConVar cvar;

	for (int i = 0; i < maxCvars; i++)
	{
		cvars.GetArray(i, cvarData);

		cvar = FindConVar(cvarData.name);
		if (cvar) 
		{	
			cvar.GetString(cvarData.originalValue, sizeof(cvarData.originalValue));
			cvar.SetString(cvarData.value);

			PrintToServer("LoadGamemode: Applying cvar: %s %s", cvarData.name, cvarData.value);
		} else {
			LogError("LoadGamemode: couldn't find cvar '%s'", cvarData.name);
		}
	}	

	g_Gamemodes.SetValue(g_PendingMode, cvars);
	strcopy(g_ActiveGamemode, sizeof(g_ActiveGamemode), modeName);
	PrintToServer("LoadGamemode: %s applied with %d cvars", g_ActiveGamemode, cvars.Length);
}