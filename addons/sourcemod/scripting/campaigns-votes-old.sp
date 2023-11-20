#include <sourcemod>
#include <anymap>
#include <morecolors>
#include <sdktools_stringtables>
#include <namecolors>

#include <maps-n-modes>
#include <nmr_instructor>

public Plugin myinfo = {
    name        = "Map & Modes (Votes)",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

#define NMR_MAXPLAYERS 9

#define MENU_NOMINATION_LEN PLATFORM_MAX_PATH + MAX_GAMEMODE_LEN + 1 

#define STRINGTABLE_NAME					"ServerMapCycle"
#define STRINGTABLE_ITEM					"ServerMapCycle"

#define NMR_MAXPLAYERS 9

Handle disableRtvTimer;
Handle beginRtvTimer;
int rtvState;

enum
{
	RTV_ALLOWED,
	RTV_EXPIRED,
	RTV_ONGOING
}

#define GAME_TYPE_OBJECTIVE 0
#define STATE_ALL_EXTRACTED 5
#define STATE_ALL_FAILED 6
#define STATE_ROUND_START 3
#define STATE_FREEZE_START 7

Menu g_FullMapMenu;

bool g_RTVed[NMR_MAXPLAYERS + 1];
char g_NominatedMap[NMR_MAXPLAYERS+1][PLATFORM_MAX_PATH];
char g_NominatedMode[NMR_MAXPLAYERS+1][MAX_GAMEMODE_LEN];

ConVar cvRtvForceAfter;
ConVar cvRTVTime;
ConVar cvFlattenMenu;
ConVar cvRtvVoteLen;
ConVar cvDefaultMode;
ConVar cvRTVBeginDelay;
ConVar cvWantedRatio;

float mapEndTime;

public void OnPluginStart()
{
	LoadTranslations("mm-map-names.phrases");
	LoadTranslations("mm-mode-names.phrases");
	LoadTranslations("mm-votes.phrases");

	cvRtvForceAfter = CreateConVar("rtv_force_after_mins", "45");
	cvRtvVoteLen = CreateConVar("rtv_panel_time", "15");
	cvFlattenMenu = CreateConVar("nominate_flatten_menu", "1");
	cvRTVTime = CreateConVar("rtv_time", "300");
	cvRTVBeginDelay = CreateConVar("rtv_delay_start", "10");
	cvWantedRatio = CreateConVar("rtv_ratio", "0.5");

	cvDefaultMode = CreateConVar("nominate_default_mode", "runners");

	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);

	RegConsoleCmd("sm_n", Cmd_Nominate, "Nominate a map to be played next");
	RegConsoleCmd("sm_nominate", Cmd_Nominate, "Nominate a map to be played next");
	RegConsoleCmd("sm_nominar", Cmd_Nominate, "Nomina un mapa para ser jugado luego");

	RegConsoleCmd("sm_rtv", Cmd_RockTheVote, "Vote to change the current map");
	RegConsoleCmd("sm_cambiar", Cmd_RockTheVote, "Vota para cambiar el mapa actual");
	//RegConsoleCmd("sm_gamemode", Cmd_Gamemode, "See current map and gamemode");
	//RegConsoleCmd("sm_modo", Cmd_Gamemode, "Ver info sobre el mapa y modo de juego actual");

	RegConsoleCmd("sm_revote", Cmd_Revote, "Undo your rtv pick");
	RegConsoleCmd("sm_nortv", Cmd_DontRockTheVote);

	RegAdminCmd("sm_forcertv", Cmd_ForceRockTheVote, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_enablertv", Cmd_EnableRTV, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_disablertv", Cmd_DisableRTV, ADMFLAG_CHANGEMAP);

	//AddCommandListener(Cmd_Callvote, "callvote");	
}

Action Cmd_Revote(int client, int args)
{
	ClearNomination(client);

	if (IsVoteInProgress())
	{
		RedrawClientVoteMenu(client);
	}

	return Plugin_Handled;
}

Action Cmd_Callvote(int client, const char[] command, int argc)
{
	if (argc < 1) {
		return Plugin_Continue;
	}

	char voteType[32];
	GetCmdArg(1, voteType, sizeof(voteType));

	if (StrEqual(voteType, "changelevel"))
	{
		char mapName[PLATFORM_MAX_PATH];
		GetCmdArg(2, mapName, sizeof(mapName));
		AttemptNominate(client, mapName);
		AttemptRTV(client);
		return Plugin_Stop;
	}

	if (StrEqual(voteType, "nextlevel"))
	{
		char mapName[PLATFORM_MAX_PATH];
		GetCmdArg(2, mapName, sizeof(mapName));
		AttemptNominate(client, mapName);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void AttemptNominate(int client, const char[] mapName)
{
	if (MapExists(mapName))
	{
		Menu_GamemodePick(client, mapName);
		return;
	}
}

bool MapExists(const char[] mapName)
{
	// TODO: This is ugly?
	ArrayList maps = MM_GetMaps();
	bool exists = maps.FindString(mapName) != -1;
	delete maps;
	return exists;
}

Action Cmd_EnableRTV(int client, int args)
{
	EnableRTV(false);
	return Plugin_Handled;
}

Action Cmd_DisableRTV(int client, int args)
{
	DisableRTV(true);
	return Plugin_Handled;
}

ArrayList g_RecentlyPlayed;

public void OnMapEnd()
{
	// char mapName[PLATFORM_MAX_PATH];
	// char modeName[MAX_GAMEMODE_LEN];

	// GetCurrentMap(mapName, sizeof(mapName));
	// MM_GetCurrentMode(modeName, sizeof(modeName));

	// char campaign[MAX_GAMEMODE_LEN+PLATFORM_MAX_PATH+1];
	// Format(campaign, sizeof(campaign), "%s %s", mapName, modeName);

	// while (g_RecentlyPlayed.Length > 5) {
	// 	g_RecentlyPlayed.Erase(0);
	// }

	// g_RecentlyPlayed.PushString(campaign);

	delete beginRtvTimer;
	delete disableRtvTimer;
	mapEndTime = 0.0;
}

bool WasCampaignPlayedRecently(const char[] campaign)
{
	return g_RecentlyPlayed.FindString(campaign) != -1;
}

public void OnMapStart()
{
	mapEndTime = GetGameTime() + cvRtvForceAfter.FloatValue * 60.0;
	ProcessMapList();
	DisableRTV(true);
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!client || IsChatTrigger())
	{
		return;
	}
	
	if (strcmp(sArgs, "rtv", false) == 0 || strcmp(sArgs, "rockthevote", false) == 0 || strcmp(sArgs, "cambiar", false) == 0)
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		AttemptRTV(client);
		
		SetCmdReplySource(old);
	}
	else if (strcmp(sArgs, "nominate", false) == 0 || strcmp(sArgs, "nominar", false) == 0)
	{
		ClientCommand(client, "sm_nominate");
	}
	else if (strcmp(sArgs, "nortv", false) == 0)
	{
		ClientCommand(client, "sm_nortv");
	}
}

public void OnClientDisconnect_Post(int client)
{
	ClearNomination(client);
	g_RTVed[client] = false;
	CheckShouldBeginRTV();
}

int GetValidVoterCount()
{
	int count = 0;
	for (int client = 1; client <= MaxClients; client++)  {
		if (InGameAndJoined(client)) {	
			count++;
		}
	}
	
	return count;
}

void CheckShouldBeginRTV()
{
	if (rtvState != RTV_ALLOWED || GetValidVoterCount() <= 0) {
		return;
	}

	int numVotes, numNeeded;
	GetNumVotes(numVotes, numNeeded);

	if (numVotes >= numNeeded) 
	{
		BeginRTVSoon();
	}
}

void BeginRTVSoon()
{
	CPrintToChatAll("%t", "RTV Starts Soon");
	rtvState = RTV_ONGOING;
	delete beginRtvTimer;
	beginRtvTimer = CreateTimer(cvRTVBeginDelay.FloatValue, Timer_BeginRTV);
}

Action Timer_BeginRTV(Handle timer)
{
	beginRtvTimer = null;
	BeginRTV();
	return Plugin_Continue;
}

void ClearNomination(int client)
{
	g_NominatedMap[client][0] = 0;
	g_NominatedMode[client][0] = 0;
}

Action Cmd_ForceRockTheVote(int client, int args)
{
	BeginRTV();
	//ReplyToCommand(client, "Forcing rock the vote");
	return Plugin_Handled;
}

Action Cmd_RockTheVote(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "Cannot RTV as console");
		return Plugin_Handled;
	}

	AttemptRTV(client);
	return Plugin_Handled;
}

Action Cmd_DontRockTheVote(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "Cannot RTV as console");
		return Plugin_Handled;
	}

	if (!g_RTVed[client]) {
		return Plugin_Handled;
	}
	
	g_RTVed[client] = false;

	int numVotes, numNeeded;
	GetNumVotes(numVotes, numNeeded);

	char playerName[MAX_NAME_LENGTH];
	ColorNameIfExists(client, playerName, sizeof(playerName));

	CPrintToChatAll("%t", "Undid RTV", playerName, numVotes, numNeeded);
	return Plugin_Handled;
}


Action Cmd_Nominate(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "Cannot nominate as console");
		return Plugin_Handled;
	}

	char filter[PLATFORM_MAX_PATH];

	// if (args < 1) 
	// {
	// 	g_FullMapMenu.Display(client, MENU_TIME_FOREVER);
	// 	return Plugin_Handled;
	// }
	
	GetCmdArg(1, filter, sizeof(filter));
	ShowNominateMenu(client, filter);
	return Plugin_Handled;
}

void ShowNominateMenu(int client, const char[] filter = "")
{
	ArrayList maps = MM_GetMaps(filter);
	
	// If our filter only has one result, nominate instantly
	if (maps.Length == 1) 
	{	
		char mapName[PLATFORM_MAX_PATH];
		maps.GetString(0, mapName, sizeof(mapName));

		ArrayList modes = MM_GetMapModes(mapName);
		if (modes.Length == 1)
		{
			char modeName[MAX_GAMEMODE_LEN];
			modes.GetString(0, modeName, sizeof(modeName));

			delete modes;

			if (IsMapAndModeNominated(mapName, modeName))
			{
				CPrintToChat(client, "%t", "Already Nominated");
				return;
			}
			
			SetNomination(client, mapName, modeName);
			return;
		}

		delete modes;
	}


	Menu menu = BuildNominateMenu(maps, filter);
	menu.Display(client, MENU_TIME_FOREVER);
	
	delete maps;
}

Menu BuildNominateMenu(ArrayList maps, const char[] filter = "")
{
	Menu menu = new Menu(MenuHandler_Nominate, MenuAction_Display|MenuAction_DisplayItem);

	if (filter[0]) {
		menu.SetTitle("Pick the next map\nFilter: \"%s\"", filter);
	} else {
		menu.SetTitle("Pick the next map");
	}

	char mapName[PLATFORM_MAX_PATH];

	int maxMaps = maps.Length;

	for (int i = 0; i < maxMaps; i++)
	{
		maps.GetString(i, mapName, sizeof(mapName));

		ArrayList modes = MM_GetMapModes(mapName);
		int maxModes = modes.Length;

		if (maxModes <= 0) 
		{
			delete modes;
			continue;
		}

		if (maxModes == 1 && cvFlattenMenu.BoolValue) 
		{	
			char modeName[MAX_GAMEMODE_LEN];
			modes.GetString(0, modeName, sizeof(modeName));
			AddMenuNomination(menu, mapName, modeName);
		}
		else 
		{
			menu.AddItem(mapName, mapName);
		}

		delete modes;
	}


	if (menu.ItemCount <= 0)
	{
		menu.AddItem("", "No maps available", ITEMDRAW_DISABLED);
	}

	return menu;
}

public void MM_OnConfigsLoaded()
{
}

int MenuHandler_Nominate(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				ShowNominateMenu(param1, "");
			}
		}

		case MenuAction_Display:
		{
			return MenuHandlerShared_Display(menu, param1, param2);
		}

		case MenuAction_DisplayItem:
		{
			return MenuHandlerShared_DisplayItem(menu, param1, param2);
		}

		case MenuAction_Select:
		{
			char mapName[PLATFORM_MAX_PATH]; 
			char modeName[MAX_GAMEMODE_LEN];

			GetMenuNomination(menu, param2, mapName, modeName);


			if (!modeName[0]) {
				Menu_GamemodePick(param1, mapName);
			} else {
				SetNomination(param1, mapName, modeName);
			}
		}
	}

	return 0;
}

void Menu_GamemodePick(int client, const char[] mapName)
{
	Menu menu = new Menu(MenuHandler_Nominate, MenuAction_Display|MenuAction_DisplayItem);

	menu.SetTitle("%T", "Pick the Game Mode", client);

	ArrayList gamemodes = MM_GetMapModes(mapName);
	int maxGamemodes = gamemodes.Length;

	char modeName[MAX_GAMEMODE_LEN];

	for (int i = 0; i < maxGamemodes; i++)
	{
		gamemodes.GetString(i, modeName, sizeof(modeName));
		AddMenuNomination(menu, mapName, modeName);
	}

	delete gamemodes;

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void SetNomination(int client, const char[] mapName, const char[] modeName)
{
	ClearNomination(client);

	char coloredName[MAX_NAME_LENGTH];
	ColorNameIfExists(client, coloredName, sizeof(coloredName));

	char mapDisplayName[64];
	TranslateIfExists(mapName, mapDisplayName, sizeof(mapDisplayName), client);


	char defaultMode[MAX_GAMEMODE_LEN];
	cvDefaultMode.GetString(defaultMode, sizeof(defaultMode));

	strcopy(g_NominatedMap[client], sizeof(g_NominatedMap[]), mapName);
	strcopy(g_NominatedMode[client], sizeof(g_NominatedMode[]), modeName);

	if (StrEqual(defaultMode, modeName))
	{
		CPrintToChatAll("%t", "Player Nominated Hide Mode", coloredName, mapDisplayName);
	}
	else
	{
		char modeDisplayName[64];
		TranslateIfExists(modeName, modeDisplayName, sizeof(modeDisplayName), client);
		CPrintToChatAll("%t", "Player Nominated", coloredName, mapDisplayName, modeDisplayName);
	}
}

void ColorNameIfExists(int client, char[] buffer, int maxlen)
{
	if (LibraryExists("namecolors")) {
		GetColoredName(client, buffer, maxlen);
	} else {
		GetClientName(client, buffer, maxlen);
	}
}

void AttemptRTV(int client)
{
	if (g_RTVed[client]) 
	{
		CPrintToChat(client, "%t", "RTV Already Issued");
		return;
	}

	if (rtvState == RTV_ONGOING)
	{
		CPrintToChat(client, "%t", "RTV is Ongoing");
		return;
	}

	if (rtvState == RTV_EXPIRED)
	{
		CPrintToChat(client, "%t", "RTV Expired");
		return;
	}


	g_RTVed[client] = true;


	char coloredName[MAX_NAME_LENGTH];
	ColorNameIfExists(client, coloredName, sizeof(coloredName));
	
	int numVotes, numNeeded;
	GetNumVotes(numVotes, numNeeded);

	CPrintToChatAll("%t", "Player RTVed", coloredName, numVotes, numNeeded);

	CheckShouldBeginRTV();
}

void GetNumVotes(int& issued, int& wanted)
{
	float wantedRatio = cvWantedRatio.FloatValue;
	int total;
	for (int client = 1; client <= MaxClients; client++) 
	{
		if (InGameAndJoined(client)) 
		{	
			if (g_RTVed[client]) {
				issued++;
			}
			total++;
		}
	}

	wanted = RoundToCeil(wantedRatio * total);
}

bool GetClientNomination(int client, char mapName[PLATFORM_MAX_PATH], char modeName[MAX_GAMEMODE_LEN])
{
	if (!g_NominatedMap[0] || !g_NominatedMode[0]) {
		return false;
	}

	strcopy(mapName, sizeof(mapName), g_NominatedMap[client]);
	strcopy(modeName, sizeof(modeName), g_NominatedMode[client]);
	return true;
}

void BeginRTV()
{
	rtvState = RTV_ONGOING;

	Menu menu = new Menu(MenuHandler_RockTheVote, MenuAction_DisplayItem|MenuAction_Display);
	menu.SetTitle("%T", "Pick the Next Map", LANG_SERVER);
	
	char mapName[PLATFORM_MAX_PATH]; char modeName[MAX_GAMEMODE_LEN];
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!InGameAndJoined(client)) {
			continue;
		}
		
		if (!GetClientNomination(client, mapName, modeName)) {
			continue;
		}

		AddMenuNomination(menu, mapName, modeName, true);
	}

	while (menu.ItemCount < 5)
	{
		if (!MM_GetRandomMapAndMode(mapName, modeName)) {
			break;    // We ran out of maps
		}

		AddMenuNomination(menu, mapName, modeName, true);
	}

	menu.AddItem("_nochange_", "Don't change");
	menu.DisplayVoteToAll(cvRtvVoteLen.IntValue);
}

bool InGameAndJoined(int client)
{
	#define STATE_WELCOME 1
	// In-game and not in the 'join game' screen
	return IsClientInGame(client) && GetEntProp(client, Prop_Send, "m_iPlayerState") != STATE_WELCOME;
}

void AddMenuNomination(Menu menu, const char[] mapName, const char[] modeName, bool strict = false)
{
	int flags = ITEMDRAW_DEFAULT;
	if (!strict && IsMapAndModeNominated(mapName, modeName)) {
		flags = ITEMDRAW_DISABLED;
	}

	if (!mapName[0] || !modeName[0]) {
		// FIXME: This is happening a lot, why?
		//LogError("Attempted to add nomination with empty mapName or modeName");
		return;
	}

	char itemInfo[MENU_NOMINATION_LEN]; char itemDisplay[255];
	Format(itemInfo, sizeof(itemInfo), "%s %s", mapName, modeName);

	Format(itemDisplay, sizeof(itemDisplay), "%s (%s)", mapName, modeName);
	menu.AddItem(itemInfo, itemDisplay, flags);
}

int MenuHandler_RockTheVote(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Display:
		{
			return MenuHandlerShared_Display(menu, param1, param2);
		}

		case MenuAction_DisplayItem:
		{
			return MenuHandlerShared_DisplayItem(menu, param1, param2);
		}

		case MenuAction_VoteCancel:
		{
			// If we receive 0 votes, pick at random.
			if (param1 == VoteCancel_NoVotes)
			{
				int count = menu.ItemCount;
				if (count <= 0) {
					return 0; // This should never happen
				}

				int itemIdx = GetRandomInt(0, count - 1);

				char mapName[PLATFORM_MAX_PATH]; char modeName[MAX_GAMEMODE_LEN];
				GetMenuNomination(menu, itemIdx, mapName, modeName);
				HandleRTVWinner(mapName, modeName);
			}
		}

		case MenuAction_VoteEnd:
		{
			char mapName[PLATFORM_MAX_PATH]; char modeName[MAX_GAMEMODE_LEN];
			GetMenuNomination(menu, param1, mapName, modeName);
			HandleRTVWinner(mapName, modeName);
		}
	}

	return 0;
}

int MenuHandlerShared_Display(Menu menu, int param1, int param2)
{
	char buffer[255];
	Format(buffer, sizeof(buffer), "%T", "Pick the Next Map", param1);
	Panel panel = view_as<Panel>(param2);
	panel.SetTitle(buffer);
	return 0;
}

int MenuHandlerShared_DisplayItem(Menu menu, int param1, int param2)
{
	char mapName[PLATFORM_MAX_PATH], modeName[MAX_GAMEMODE_LEN];
	GetMenuNomination(menu, param2, mapName, modeName);

	if (StrEqual(mapName, "_nochange_"))
	{
		char itemDisplay[255];
		Format(itemDisplay, sizeof(itemDisplay), "%T", "Don't Change", param1);
		return RedrawMenuItem(itemDisplay);
	}

	if (!mapName[0]) {
		return 0;
	}

	char defaultMode[MAX_GAMEMODE_LEN];
	cvDefaultMode.GetString(defaultMode, sizeof(defaultMode));
	
	char mapDisplayName[255];
	TranslateIfExists(mapName, mapDisplayName, sizeof(mapDisplayName), param1);

	char itemDisplay[255];
	if (!modeName[0] || StrEqual(modeName, defaultMode))
	{
		Format(itemDisplay, sizeof(itemDisplay), "%s", mapDisplayName);
		return RedrawMenuItem(itemDisplay);
	}

	char modeDisplayName[255];
	TranslateIfExists(modeName, modeDisplayName, sizeof(modeDisplayName), param1);

	Format(itemDisplay, sizeof(itemDisplay), "%s (%s)", mapDisplayName, modeDisplayName);
	return RedrawMenuItem(itemDisplay);
}

void GetMenuNomination(Menu menu, int index, char mapName[PLATFORM_MAX_PATH], char modeName[MAX_GAMEMODE_LEN])
{
	char selection[MENU_NOMINATION_LEN];
	menu.GetItem(index, selection, sizeof(selection));
	
	for (int i = 0; selection[i]; i++)
	{
		if (selection[i] == ' ') 
		{
			selection[i] = '\0';
			strcopy(mapName, sizeof(mapName), selection);
			strcopy(modeName, sizeof(modeName), selection[i+1]);
			return;
		}
	}

	// Else the whole thing is the map name
	strcopy(mapName, sizeof(mapName), selection);
}

void HandleRTVWinner(const char[] mapName, const char[] modeName)
{
	if (StrEqual(mapName, "_nochange_"))
	{
		CPrintToChatAll("%t", "Staying in Map");
		mapEndTime = GetGameTime() + cvRtvForceAfter.FloatValue * 60.0;
		return;
	}

	char mapDisplayName[64], modeDisplayName[64];

	for (int client = 1; client <= MaxClients; client++) 
	{
		if (!IsClientInGame(client)) {
			continue;
		}

		TranslateIfExists(mapName, mapDisplayName, sizeof(mapDisplayName), client);

		char defaultMode[MAX_GAMEMODE_LEN];
		cvDefaultMode.GetString(defaultMode, sizeof(defaultMode));

		if (StrEqual(defaultMode, modeName))
		{
			CPrintToChat(client, "%t", "RTV Vote Ended Hide Mode", mapDisplayName);
		}
		else
		{
			TranslateIfExists(modeName, modeDisplayName, sizeof(modeDisplayName), client);
			CPrintToChat(client, "%t", "RTV Vote Ended", mapDisplayName, modeDisplayName);
		}
	}

	MM_SetNextMapAndMode(mapName, modeName);
	CreateTimer(5.0, Timer_ChangeMapAndMode);
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	delete disableRtvTimer;
	EnableRTV(true);

	if (GetGameTime() > mapEndTime) {
		BeginRTVSoon();
	}
}

Action Timer_UnloadRTV(Handle timer)
{
	disableRtvTimer = null;
	DisableRTV();
	return Plugin_Continue;
}

void ProcessMapList()
{
	int stringTableIndex = FindStringTable(STRINGTABLE_NAME);
	int stringIndex = FindStringIndex(stringTableIndex, STRINGTABLE_ITEM);

	// Maplist resets every map
	int length = GetStringTableDataLength(stringTableIndex, stringIndex);
	char[] mapData = new char[length];
	GetStringTableData(stringTableIndex, stringIndex, mapData, length);

	// We'll get an extra blank entry if we don't do this
	TrimString(mapData);

	char newData[4092];

	ArrayList maps = MM_GetMaps();
	int maxMaps = maps.Length;

	char mapName[PLATFORM_MAX_PATH];

	for (int i = 0; i < maxMaps; i++)
	{
		maps.GetString(i, mapName, sizeof(mapName));
		
		ArrayList modes = MM_GetMapModes(mapName);
		int maxModes = modes.Length;

		for (int j = 0; j < maxModes; j++)
		{
			char modeName[MAX_GAMEMODE_LEN];
			modes.GetString(j, modeName, sizeof(modeName));

			Format(newData, sizeof(newData), "%s\n%s (%s)", newData, mapName, modeName, LANG_SERVER);
		}

		delete modes;
	}

	SetStringTableData(stringTableIndex, stringIndex, newData, sizeof(newData));
}

Action Timer_ChangeMapAndMode(Handle timer, any data)
{
	MM_ChangeMapAndMode();
	return Plugin_Continue;
}

void EnableRTV(bool timed)
{
	FindConVar("sv_vote_issue_restart_game_allowed").BoolValue = true;
	rtvState = RTV_ALLOWED;
	CPrintToChatAll("%t", "RTV Enabled Timed", cvRTVTime.IntValue);

	delete disableRtvTimer;
	disableRtvTimer = CreateTimer(cvRTVTime.FloatValue, Timer_UnloadRTV);
}

void DisableRTV(bool silent = false)
{	
	FindConVar("sv_vote_issue_restart_game_allowed").BoolValue = false;
	rtvState = RTV_EXPIRED;
	if (!silent) {
		CPrintToChatAll("%t", "RTV Disabled");
	}
}

bool IsMapAndModeNominated(const char[] mapName, const char[] modeName)
{
	// TODO: Not great perf wise, maybe we should use a StringMap instead of looping

	for (int client = 1; client <= MaxClients; client++) 
	{
		if (!InGameAndJoined(client)) {
			continue;
		}

		if (StrEqual(mapName, g_NominatedMap[client]) && 
			StrEqual(modeName, g_NominatedMode[client]))
		{
			return true;
		}
	}

	return false;
}

void TranslateIfExists(const char[] str, char[] result, int maxlen, int lang)
{
	if (TranslationPhraseExists(str)) {
		Format(result, maxlen, "%T", str, lang)
	} else {
		strcopy(result, maxlen, str);
	}
}