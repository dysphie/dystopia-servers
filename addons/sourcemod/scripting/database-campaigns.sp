
#include <sourcemod>
#include <morecolors>
#include <campaigns>
#include <sdktools>
#pragma semicolon 1

#define NMR_MAXPLAYERS	 9

#define SND_VOTE_YES "ui/vote_yes.wav"

ArrayList g_CampaignsArray;
StringMap g_CampaignsMap;
StringMap g_Gamemodes;

Handle endRtvtimer;
ArrayList g_ChangedCvars;

public Plugin myinfo =
{
	name = "Campaign Manager",
	author = "Dysphie",
	description = "",
	version = "",
	url = ""
};

enum struct GamemodeCvar
{
	char name[64];
	char value[64];
	char originalValue[64];
}

bool g_WantsChange[NMR_MAXPLAYERS + 1];

#define RTV_DISABLED	  0
#define RTV_ENABLED		  1
#define RTV_VOTE_STARTING 2
#define RTV_VOTE_ONGOING  3

#define MAX_RTV_OPTIONS	  5

int		  g_RtvStatus = RTV_ENABLED;	// fixme

char	  g_Nomination[NMR_MAXPLAYERS + 1][MAX_CAMPAIGN_LEN];

char	  g_CurrentCampaign[MAX_CAMPAIGN_LEN];

int g_NumRevotes[NMR_MAXPLAYERS+1];

ConVar	  cvNextCampaign;
StringMap g_CallvoteKeys;

float g_MapBeginTime;

GlobalForward g_ReadyForward;

enum struct RtvOption
{
	char campaign[MAX_CAMPAIGN_LEN];
	int	 votes;
	int	 vetoerSerial;
	bool vetoed;

	void Clear()
	{
		this.votes	  = 0;
		this.campaign = ""; 
		this.vetoed = false;
		this.vetoerSerial = 0;
	}
}

Menu	  g_NominateMenu;

int		  g_NumRtvOptions = 0;
RtvOption g_Choices[MAX_RTV_OPTIONS];

int		  g_Voted[NMR_MAXPLAYERS + 1] = { -1, ... };

Handle	  g_RtvTimer;

StringMap g_PlayerBans;

ConVar	  cvVetoLimit;
ConVar cvCooldownTime;

bool	  g_RtvOnNextReset;

bool g_ConfigsLoaded;

ConVar cvRtvTime;
ConVar cvRestartAllow;
ConVar cvMapLimit;
ConVar cvRtvDelay;
ConVar cvLockVoteOption;
ConVar cvNumRevotes;

public void OnPluginStart()
{
	g_ReadyForward = new GlobalForward("OnCampaignsLoaded", ET_Ignore);

	cvNumRevotes = CreateConVar("rtv_max_revotes", "3");
	cvMapLimit = CreateConVar("rtv_map_limit", "60");
	cvVetoLimit		 = CreateConVar("rtv_veto_limit", "2");
	cvRtvTime = CreateConVar("rtv_time", "300");
	cvRtvDelay = CreateConVar("rtv_start_delay", "15");

	cvLockVoteOption = CreateConVar("rtv_vote_key_lock", "1");

	g_Gamemodes = new StringMap();
	g_PlayerBans	 = new StringMap();
	g_CallvoteKeys	 = new StringMap();
	g_CampaignsArray = new ArrayList(ByteCountToCells(MAX_CAMPAIGN_LEN));
	g_CampaignsMap	 = new StringMap();
	g_ChangedCvars = new ArrayList(sizeof(GamemodeCvar));

	RegisterGamemodes();
	RegisterMaps();
	g_ConfigsLoaded = true;

	LoadTranslations("map-names.phrases");
	LoadTranslations("mode-names.phrases");
	LoadTranslations("campaigns.phrases");

	cvRestartAllow = FindConVar("sv_vote_issue_restart_game_allowed");

	RegConsoleCmd("sm_nominate", Cmd_Nominate);
	RegConsoleCmd("sm_nominar", Cmd_Nominate);
	RegConsoleCmd("sm_n", Cmd_Nominate);
	RegConsoleCmd("sm_rtv", Cmd_Rtv);
	RegConsoleCmd("sm_cambiar", Cmd_Rtv);
	RegConsoleCmd("sm_nortv", Cmd_UndoRtv);
	RegConsoleCmd("sm_nocambiar", Cmd_UndoRtv);
	RegConsoleCmd("sm_veto", Cmd_Veto);
	RegConsoleCmd("currentcampaign", Cmd_CurrentCampaign);


	RegAdminCmd("sm_forcertv", Cmd_ForceRtv, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_forceendrtv", Cmd_ForceEndRtv, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_enablertv", Cmd_EnableRtv, ADMFLAG_CHANGEMAP);
	RegAdminCmd("sm_disablertv", Cmd_DisableRtv, ADMFLAG_CHANGEMAP);
	RegAdminCmd("dump_rtv_options", Cmd_DumpRtvOptions, ADMFLAG_CHANGEMAP);
	RegAdminCmd("reload_nominate_menu", Cmd_ReloadNominateMenu, ADMFLAG_CHANGEMAP);
	RegAdminCmd("dump_campaign_cooldowns", Cmd_DumpCampaignCooldowns, ADMFLAG_CHANGEMAP);

	RegAdminCmd("changecampaign", Cmd_Campaign, ADMFLAG_CHANGEMAP);
	RegAdminCmd("changecampaign_next", Cmd_CampaignNext, ADMFLAG_CHANGEMAP);
	//RegAdminCmd("make_played", Cmd_MakePlayed, ADMFLAG_CHANGEMAP);

	HookEvent("player_extracted", Event_PlayerExtracted, EventHookMode_PostNoCopy);

	cvNextCampaign = CreateConVar("nextcampaign", "", "Houses the next campaign");
	cvCooldownTime = CreateConVar("veto_cooldown_minutes", "60", "Time after vetoing a campaign before it can be played again");

	// LoadDummyCampaigns();

	AddCommandListener(Command_RtvVote, "vote");
	AddCommandListener(Cmd_Callvote, "callvote");

	g_NominateMenu = BuildNominateMenu();

	HookEvent("nmrih_reset_map", Event_OnMapReset);
}

Action Cmd_CurrentCampaign(int client, int args)
{
	char modeName[MAX_GAMEMODE_LEN];
	char mapName[PLATFORM_MAX_PATH];

	DeserializeCampaign(g_CurrentCampaign, mapName, sizeof(mapName), modeName, sizeof(modeName));

	if (!mapName[0]) {
		GetCurrentMap(mapName, sizeof(mapName));
	}

	CReplyToCommand(client, "The current campaign is %s %s", mapName, modeName);
	return Plugin_Handled;
}

public void OnPluginEnd()
{
	RevertChangedCvars();
}

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

void Event_PlayerExtracted(Event event, const char[] name, bool dontBroadcast)
{
	g_RtvOnNextReset = true;
}

Action Cmd_ForceEndRtv(int client, int args)
{
	EndRtvVote();
	return Plugin_Handled;
}

Action Cmd_Veto(int client, int args)
{
	if (g_RtvStatus != RTV_VOTE_ONGOING)
	{
		CReplyToCommand(client, "%t", "Veto Only Available During Vote");
		return Plugin_Handled;
	}

	char steamid[64];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));

	int timesVetoed;
	if (g_PlayerBans.GetValue(steamid, timesVetoed) && timesVetoed >= cvVetoLimit.IntValue)
	{
		CReplyToCommand(client, "%t", "Reached Veto Limit", cvVetoLimit.IntValue);
		return Plugin_Handled;
	}

	int choice = GetCmdArgInt(1) - 1;
	if (!IsValidChoice(choice))
	{
		return Plugin_Handled;
	}

	char display[255];
	CampaignToDisplayName(g_Choices[choice].campaign, display, sizeof(display), client);
	CPrintToChatAll("%t", "Player Vetoed Map", client, display);
	g_Choices[choice].vetoed	   = true;
	g_Choices[choice].vetoerSerial = GetClientSerial(client);
	AddCooldown(g_Choices[choice].campaign, cvCooldownTime.FloatValue);

	ResendEntireVote();
	Event_VoteCast(client, choice);

	g_PlayerBans.SetValue(steamid, ++timesVetoed);
	return Plugin_Handled;
}

void ResendEntireVote()
{
	Event_VoteOptions();
	Event_VoteStart();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsValidChoice(g_Voted[i]))
		{
			continue;
		}

		Event_VoteCast(i, g_Voted[i], true);
	}
}

void Event_VoteStart()
{
	char text[255];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		FormatEx(text, sizeof(text), "%T\n\n\n\n\n\n\n\n\n\n", "RTV Panel Title", i);

		Handle	msg = StartMessageOne("VoteStart", i, USERMSG_RELIABLE);
		BfWrite bf	= UserMessageToBfWrite(msg);
		bf.WriteByte(0);					// m_iOnlyTeamToVote
		bf.WriteByte(99);					// m_iEntityHoldingVote
		bf.WriteString("#SDK_Chat_All");	// pCurrentIssue->GetDisplayString()
		bf.WriteString(text);				// pCurrentIssue->GetDetailsString()
		bf.WriteBool(false);				// pCurrentIssue->IsYesNoVote()
		EndMessage();
	}
}

void AddCooldown(const char[] campaign, float minutes)
{
	g_CampaignsMap.SetValue(campaign, GetEngineTime() + minutes * 60.0);
	PrintToServer("Placing %s on cooldown for %f minutes", campaign, minutes);
}

Action Cmd_DumpCampaignCooldowns(int client, int args)
{
	int	 maxCampaigns = g_CampaignsArray.Length;
	char campaign[MAX_CAMPAIGN_LEN];

	float curTime = GetEngineTime();
	for (int i = 0; i < maxCampaigns; i++)
	{
		g_CampaignsArray.GetString(i, campaign, sizeof(campaign));

		float cooldownEndTime = -1.0;
		g_CampaignsMap.GetValue(campaign, cooldownEndTime);

		if (curTime < cooldownEndTime)
		{
			PrintToServer("%s: %f", campaign, cooldownEndTime - curTime);
		}
	}

	return Plugin_Handled;
}

Action Cmd_CampaignNext(int client, int args)
{
	ChangeToNextCampaign("Console");
	return Plugin_Handled;
}

Action Cmd_Campaign(int client, int args)
{
	char campaign[MAX_CAMPAIGN_LEN];

	char mapName[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapName, sizeof(mapName));

	char modeName[PLATFORM_MAX_PATH];
	GetCmdArg(2, modeName, sizeof(modeName));

	SerializeCampaign(mapName, modeName, campaign, sizeof(campaign));

	TrimString(campaign); // Remove trailing space, todo: why does this happen

	if (!g_CampaignsMap.ContainsKey(campaign))
	{
		ReplyToCommand(client, "Campaign load failed: '%s' not found", campaign);
		return Plugin_Handled;
	}

	cvNextCampaign.SetString(campaign);
	ChangeToNextCampaign();

	return Plugin_Handled;
}

public void OnMapEnd()
{
	RevertChangedCvars();

	if (g_CurrentCampaign[0])
	{
		AddCooldown(g_CurrentCampaign, GetMapElapsedTimeMins() * 2.0);
	}

	g_CurrentCampaign[0] = '\0';
	g_RtvTimer = null;	  // Reflect TIMER_FLAG_NO_MAPCHANGE flag behavior
	g_RtvOnNextReset = false;
}

Action Cmd_EnableRtv(int client, int args)
{

	EnableRtv();	
	
	if (GetCmdArgInt(1) != 1) {	
		CPrintToChatAll("%t", "Admin Enabled RTV", client);
	}

	return Plugin_Handled;
}

void EnableRtv()
{
	//cvChangeLevelAllow.BoolValue = true;
	cvRestartAllow.BoolValue = true;
	//cvNextLevelAllow.BoolValue = true;

	g_RtvStatus = RTV_ENABLED;

	CheckShouldStartVote();
}

void CheckShouldStartVote()
{
	if (GetClientCount() < 1) {
		return;
	}

	int issued, wanted;
	GetRtvRatio(issued, wanted);

	if (issued == wanted)
	{
		BeginRtv();
	}
}

public void OnMapStart()
{
	PrecacheSound(SND_VOTE_YES);
	g_MapBeginTime = GetEngineTime();

	char nextCampaign[MAX_CAMPAIGN_LEN];
	cvNextCampaign.GetString(nextCampaign, sizeof(nextCampaign));

	if (nextCampaign[0])
	{
		char modeName[MAX_GAMEMODE_LEN];
		DeserializeCampaign(nextCampaign, .modeName = modeName, .modeNameLen = sizeof(modeName));

		LoadGamemode(modeName);

		strcopy(g_CurrentCampaign, sizeof(g_CurrentCampaign), nextCampaign);
		cvNextCampaign.SetString("");
	}

	HandleNoCampaign();
	OverrideMapcycleStringTable();
}

void HandleNoCampaign()
{
	if (g_CurrentCampaign[0]) 
	{
		LogMessage("HandleNoCampaign called but g_CurrentCampaign is %s", g_CurrentCampaign);
		return;
	}
	
	LogMessage("Invalid current campaign, picking random gamemode...");
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));

	ArrayList gamemodes = GetMapGamemodes(mapName);
	int maxGamemodes = gamemodes.Length;
	if (maxGamemodes > 0)
	{
		int rnd = GetRandomInt(0, maxGamemodes - 1);

		char randomMode[MAX_GAMEMODE_LEN];
		gamemodes.GetString(rnd, randomMode, sizeof(randomMode));
		LogMessage("Picked random gamemode '%s'", randomMode);

		LoadGamemode(randomMode);

		SerializeCampaign(mapName, randomMode, g_CurrentCampaign, sizeof(g_CurrentCampaign));
	}
	else
	{
		LogMessage("Map '%s' has no available gamemodes, we are in an invalid state!", mapName);
	}

	delete gamemodes;
}

ArrayList GetMapGamemodes(const char[] targetMapName)
{
	ArrayList gamemodes = new ArrayList(ByteCountToCells(MAX_GAMEMODE_LEN));

	int maxCampaigns = g_CampaignsArray.Length;
	char campaign[MAX_CAMPAIGN_LEN];

	char mapName[PLATFORM_MAX_PATH];
	char modeName[MAX_GAMEMODE_LEN];

	for (int i = 0; i < maxCampaigns; i++)
	{
		g_CampaignsArray.GetString(i, campaign, sizeof(campaign));
		DeserializeCampaign(campaign, mapName, sizeof(mapName), modeName, sizeof(modeName));

		if (StrEqual(mapName, targetMapName)) {
			gamemodes.PushString(modeName);
		}
	}

	return gamemodes;
}

Action Cmd_DisableRtv(int client, int args)
{
	DisableRtv();

	if (GetCmdArgInt(1) != 1) {	
		CPrintToChatAll("%t", "Admin Disabled RTV", client);
	}

	return Plugin_Handled;
}

Menu BuildNominateMenu(const char[] filter = "")
{
	ArrayList maps = g_CampaignsArray;

	Menu	  menu = new Menu(MenuHandler_Nominate, MenuAction_Display | MenuAction_DisplayItem | MenuAction_DrawItem);

	if (filter[0])
	{
		menu.SetTitle("Pick the next map\nFilter: \"%s\"", filter);
	}
	else {
		menu.SetTitle("Pick the next map");
	}

	char campaign[MAX_CAMPAIGN_LEN];

	int	 maxCampaigns = maps.Length;

	for (int i = 0; i < maxCampaigns; i++)
	{
		maps.GetString(i, campaign, sizeof(campaign));

		if (filter[0] && StrContains(campaign, filter, false) == -1)
		{
			continue;
		}

		menu.AddItem(campaign, campaign);
	}

	if (menu.ItemCount <= 0)
	{
		menu.AddItem("", "No maps available", ITEMDRAW_DISABLED);
	}

	return menu;
}

void Event_OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	delete g_RtvTimer;
	EnableRtv();
	g_RtvTimer	= CreateTimer(cvRtvTime.FloatValue, Timer_DisableRTV, _, TIMER_FLAG_NO_MAPCHANGE);

	if (g_RtvOnNextReset || GetMapElapsedTimeMins() > cvMapLimit.FloatValue)
	{
		g_RtvOnNextReset = false;
		BeginRtvCountdown();
	}
}

float GetMapElapsedTimeMins()
{
	if (!g_MapBeginTime) {
		return 0.0;
	}

	return (GetEngineTime() - g_MapBeginTime) / 60.0;
}

void BeginRtvCountdown()
{
	g_RtvStatus = RTV_VOTE_STARTING;
	CPrintToChatAll("%t", "RTV Starting Soon", cvRtvDelay.IntValue);
	CreateTimer(cvRtvDelay.FloatValue, Timer_BeginRtv, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_BeginRtv(Handle timer, any data)
{
	BeginRtv();
	return Plugin_Stop;
}

Action Timer_DisableRTV(Handle timer, any data)
{
	if (g_RtvStatus == RTV_ENABLED)
	{
		CPrintToChatAll("%t", "RTV Disabled Until Next Round");
		DisableRtv();
	}

	g_RtvTimer = null;
	
	return Plugin_Continue;
}

void DisableRtv()
{
	g_RtvStatus = RTV_DISABLED;
	cvRestartAllow.BoolValue = false;
}

Action Cmd_UndoRtv(int client, int args)
{
	if (!g_WantsChange[client])
	{
		CReplyToCommand(client, "%t", "Can't Undo RTV");
		return Plugin_Handled;
	}

	UndoRtv(client);
	return Plugin_Handled;
}

void UndoRtv(int client)
{
	g_WantsChange[client] = false;

	int issued, wanted;
	GetRtvRatio(issued, wanted);

	CPrintToChatAll("%t", "Client retracted RTV", client, issued, wanted);
}

Action Cmd_ReloadNominateMenu(int client, int args)
{
	return Plugin_Handled;
}

int MenuHandler_Nominate(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			if (menu != g_NominateMenu)
			{
				delete menu;
			}
		}
		case MenuAction_Select:
		{
			int	 selection = param2;
			int	 client	   = param1;

			char campaign[MAX_CAMPAIGN_LEN];
			menu.GetItem(selection, campaign, sizeof(campaign));

			char rejectPhrase[255];
			if (!CouldNominateCampaign(campaign, rejectPhrase, sizeof(rejectPhrase)))
			{
				CPrintToChat(client, rejectPhrase);
				return 0;
			}

			NominateCampaign(client, campaign);
		}

		case MenuAction_Display:
		{
			int client = param1;

			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", "Nominate Panel Title", client);

			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(buffer);
		}

		case MenuAction_DrawItem:
		{
			int	 style;
			char campaign[MAX_CAMPAIGN_LEN];
			menu.GetItem(param2, campaign, sizeof(campaign), style);

			if (!CouldNominateCampaign(campaign))
			{
				return ITEMDRAW_DISABLED;
			}

			return style;
		}

		case MenuAction_DisplayItem:
		{
			int	 selection = param2;
			int	 client	   = param1;

			char campaign[MAX_CAMPAIGN_LEN];
			menu.GetItem(selection, campaign, sizeof(campaign));

			char rejectPhrase[255];
			bool allowed = CouldNominateCampaign(campaign, rejectPhrase, sizeof(rejectPhrase));

			char display[64];
			CampaignToDisplayName(campaign, display, sizeof(display), client);

			if (!allowed)
			{
				Format(display, sizeof(display), "%s (%s)", display, rejectPhrase);
			}

			return RedrawMenuItem(display);
		}
	}

	return 0;
}

Action Cmd_DumpRtvOptions(int client, int args)
{
	for (int i = 0; i < sizeof(g_Choices); i++)
	{
		if (i == g_NumRtvOptions)
		{
			ReplyToCommand(client, "---- limit %d ----", g_NumRtvOptions);
		}
		ReplyToCommand(client, "Option %d: %s - %d", i, g_Choices[i].campaign, g_Choices[i].votes);
	}

	return Plugin_Handled;
}

Action Cmd_Callvote(int client, const char[] command, int argc)
{
	if (argc < 2)
	{
		return Plugin_Continue;
	}

	char fullArg[128];
	char arg[64];
	
	for (int i = 2; i <= argc; i++)
	{
		GetCmdArg(i, arg, sizeof(arg));
		Format(fullArg, sizeof(fullArg), "%s%s", fullArg, arg);
	}

	char commandType[32];
	char campaign[MAX_CAMPAIGN_LEN];
	GetCmdArg(1, commandType, sizeof(commandType));

	if (StrEqual(commandType, "changelevel"))
	{
		g_CallvoteKeys.GetString(fullArg, campaign, sizeof(campaign));

		char rejectPhrase[255];
		if (!CouldNominateCampaign(campaign, rejectPhrase, sizeof(rejectPhrase)))
		{
			CPrintToChat(client, rejectPhrase);
			return Plugin_Handled;
		}

		NominateCampaign(client, campaign);

		if (!CouldRtv(client, rejectPhrase, sizeof(rejectPhrase)))
		{
			CPrintToChat(client, rejectPhrase);
		}
		else {
			Rtv(client);
		}

		return Plugin_Handled;
	}

	else if (StrEqual(commandType, "restart"))
	{
		if (!IsPlayerAlive(client))
		{
			CPrintToChat(client, "Debes estar vivo para usar restart");
			return Plugin_Handled;
		}

		return Plugin_Continue;
	}

	else if (StrEqual(commandType, "nextlevel"))
	{
		g_CallvoteKeys.GetString(fullArg, campaign, sizeof(campaign));

		char rejectPhrase[255];
		if (!CouldNominateCampaign(campaign))
		{
			CPrintToChat(client, "%t: %t", "Can't Nominate", rejectPhrase);
			return Plugin_Handled;
		}

		NominateCampaign(client, campaign);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

Action Command_RtvVote(int client, const char[] command, int argc)
{
	if (g_RtvStatus != RTV_VOTE_ONGOING)
	{
		return Plugin_Continue;
	}

	char arg[8];
	GetCmdArg(1, arg, sizeof(arg));

	if (strncmp(arg, "option", 6) != 0)
	{
		return Plugin_Continue;
	}

	int option = StringToInt(arg[6]) - 1;
	if (!IsValidChoice(option))
	{
		return Plugin_Continue;
	}

	VoteCast(client, option);

	CreateTimer(0.1, Timer_CheckShouldEndVote);


	return Plugin_Handled;
}

Action Timer_CheckShouldEndVote(Handle timer, any data)
{
	CheckShouldEndVote();
	return Plugin_Continue;
}

bool IsValidChoice(int option)
{
	return 0 <= option < g_NumRtvOptions;
}

void CheckShouldEndVote()
{
	if (g_RtvStatus != RTV_VOTE_ONGOING) {
		return;
	}

	int totalClients = 0;
	int totalVoted	 = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			totalClients++;
			if (g_Voted[i] != -1)
			{
				totalVoted++;
			}
		}
	}

	if (totalVoted == totalClients)
	{
		EndRtvVote();
	}
}

void VoteCast(int client, int option)
{
	int currentVote = g_Voted[client];
	if (currentVote == option)
	{
		return;
	}

	if (g_NumRevotes[client] > cvNumRevotes.IntValue) {
		return;
	}

	if (currentVote != -1)
	{
		g_Choices[currentVote].votes--;
	}

	g_Choices[option].votes++;
	g_Voted[client] = option;

	if (cvLockVoteOption.BoolValue) {
		Event_VoteCast(client, option);
	} else {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				EmitSoundToClient(i, SND_VOTE_YES);
			}
		}
	}

	Event_VoteChanged();
	g_NumRevotes[client]++;
}

void Event_VoteCast(int client, int option, bool singlePlayer = false)
{
	Event event = CreateEvent("vote_cast");
	event.SetInt("vote_option", option);
	event.SetInt("team", 0);
	event.SetInt("entityid", client);

	if (!singlePlayer)
	{
		event.Fire();
	}
	else {
		event.FireToClient(client);
		event.Cancel();
	}
}

Action Cmd_ForceRtv(int client, int args)
{
	BeginRtvCountdown();
	PrintToChatAll("%N forced Rtv vote", client);
	return Plugin_Handled;
}

// void LoadDummyCampaigns()
// {
// 	RegisterCampaign("frosty_fjords#runners");
// 	RegisterCampaign("jungle_ruins#runners");
// 	RegisterCampaign("desert_oasis#runners");
// 	RegisterCampaign("snowblind_summit#runners");
// 	RegisterCampaign("abandoned_asylum#runners");
// 	RegisterCampaign("haunted_hills#escort");
// 	RegisterCampaign("space_station_alpha#sabotage");
// 	RegisterCampaign("underwater_trench#runners");
// 	RegisterCampaign("medieval_castle#runners");
// 	RegisterCampaign("futuristic_city#runners");
// }

void RegisterCampaign(const char[] campaign)
{
	g_CampaignsArray.PushString(campaign);
	g_CampaignsMap.SetValue(campaign, -1.0);
}

Action Cmd_Rtv(int client, int args)
{
	char rejectPhrase[255];
	if (!CouldRtv(client, rejectPhrase, sizeof(rejectPhrase)))
	{
		CReplyToCommand(client, "{lightpink}%t", rejectPhrase);
		return Plugin_Handled;
	}

	Rtv(client);
	return Plugin_Handled;
}

Action Cmd_Nominate(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}

	char filter[PLATFORM_MAX_PATH];
	GetCmdArg(1, filter, sizeof(filter));

	Menu menu = filter[0] ? BuildNominateMenu(filter) : g_NominateMenu;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

void NominateCampaign(int client, const char[] campaign)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		char display[255];
		CampaignToDisplayName(campaign, display, sizeof(display), i);

		if (g_Nomination[client][0])
		{
			CPrintToChat(i, "%t", "Client Switched Nomination", client, display);
		}
		else
		{
			CPrintToChat(i, "%t", "Client Nominated", client, display);
		}
	}

	strcopy(g_Nomination[client], sizeof(g_Nomination[]), campaign);
}

bool Rtv(int client)
{
	g_WantsChange[client] = true;

	int issued, wanted;
	GetRtvRatio(issued, wanted);

	CPrintToChatAll("%t", "Client Did RTV", client, issued, wanted);

	if (issued == wanted)
	{
		BeginRtvCountdown();
	}

	return true;
}

bool CouldRtv(int client, char[] rejectPhrase, int maxlen)
{
	if (g_RtvStatus != RTV_ENABLED)
	{
		if (g_RtvStatus == RTV_VOTE_STARTING)
		{
			FormatEx(rejectPhrase, maxlen, "RTV is about to start");
		}
		else if (g_RtvStatus == RTV_VOTE_ONGOING) {
			FormatEx(rejectPhrase, maxlen, "RTV is already ongoing");
		}
		else {
			FormatEx(rejectPhrase, maxlen, "RTV is currently disabled");
		}

		return false;
	}

	if (g_WantsChange[client])
	{
		FormatEx(rejectPhrase, maxlen, "You already rtved");
		return false;
	}

	if (!IsPlayerAlive(client)) {
		FormatEx(rejectPhrase, maxlen, "Dead cant rtv");
		return false;
	}

	return true;
}

public void OnClientDisconnect(int client)
{
	g_WantsChange[client]	= false;
	g_Nomination[client][0] = '\0';
	g_Voted[client]			= -1;
	g_NumRevotes[client] = 0;
}

void BeginRtv()
{
	delete g_RtvTimer;

	int maxCampaigns = g_CampaignsArray.Length;
	if (maxCampaigns <= 0)
	{
		return;
	}

	// Clear any leftover votes
	for (int i = 0; i < sizeof(g_Choices); i++)
	{
		g_Choices[i].Clear();
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		g_Voted[i] = -1;
	}

	g_NumRtvOptions = 0;
	g_RtvStatus		= RTV_VOTE_ONGOING;

	// Copy client nominations
	for (int client = 1; client <= MaxClients && g_NumRtvOptions < MAX_RTV_OPTIONS; client++)
	{
		if (!IsClientInGame(client) || !g_Nomination[client][0])
		{
			continue;
		}

		g_Choices[g_NumRtvOptions].campaign = g_Nomination[client];
		g_NumRtvOptions++;
	}

	// Fill in remaining slots with random campaigns
	for (int attempts = 20; attempts > 0 && g_NumRtvOptions < MAX_RTV_OPTIONS; attempts--)
	{
		int	 rnd = GetRandomInt(0, g_CampaignsArray.Length - 1);

		char campaign[MAX_CAMPAIGN_LEN];
		g_CampaignsArray.GetString(rnd, campaign, sizeof(campaign));

		if (!CouldNominateCampaign(campaign)) {
			continue;
		}

		g_Choices[g_NumRtvOptions].campaign = campaign;
		g_NumRtvOptions++;
	}

	Event_VoteOptions();
	Event_VoteStart();
	Event_VoteChanged();

	endRtvtimer = CreateTimer(20.0, Timer_EndRtv, _, TIMER_FLAG_NO_MAPCHANGE);
}

void Event_VoteOptions()
{
	char display[255];

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
		{
			continue;
		}

		Event event = CreateEvent("vote_options");
		event.SetInt("count", g_NumRtvOptions);

		for (int i = 0; i < g_NumRtvOptions; i++)
		{
			char key[8];
			Format(key, sizeof(key), "option%d", i + 1);

			if (g_Choices[i].vetoed)
			{
				Format(display, sizeof(display), "%T", "Vetoed", client);
			}
			else {
				CampaignToDisplayName(g_Choices[i].campaign, display, sizeof(display), client);
			}

			event.SetString(key, display);
		}

		event.FireToClient(client);
		event.Cancel();
	}
}

void CampaignToDisplayName(const char[] campaign, char[] displayName, int displayNameLen, int lang)
{
	char mapName[PLATFORM_MAX_PATH];
	char modeName[MAX_GAMEMODE_LEN];

	DeserializeCampaign(campaign, mapName, sizeof(mapName), modeName, sizeof(modeName));

	if (!mapName[0] && !modeName[0])
	{
		strcopy(displayName, displayNameLen, campaign);
		return;
	}

	TranslateIfExists(mapName, sizeof(mapName), lang);

	if (StrEqual(modeName, "runners"))	  // HACK
	{
		Format(displayName, displayNameLen, "%s", mapName);
	}
	else
	{
		TranslateIfExists(modeName, sizeof(modeName), lang);
		Format(displayName, displayNameLen, "%s (%s)", mapName, modeName);
	}
}

void TranslateIfExists(char[] buffer, int maxlen, int lang)
{
	if (TranslationPhraseExists(buffer))
	{
		Format(buffer, maxlen, "%T", buffer, lang);
	}
}

Action Timer_EndRtv(Handle timer)
{
	endRtvtimer = null;
	EndRtvVote();
	return Plugin_Continue;
}

bool CouldNominateCampaign(const char[] campaign, char[] rejectPhrase = "", int maxlen = 0)
{
	if (StrEqual(campaign, g_CurrentCampaign))
	{
		FormatEx(rejectPhrase, maxlen, "Current map");
		return false;
	}

	float cooldownEndTime = -1.0;
	if (!g_CampaignsMap.GetValue(campaign, cooldownEndTime))
	{
		FormatEx(rejectPhrase, maxlen, "Doesn't exist", campaign);
		return false;
	}

	// PrintToServer("cur: %f, cooldown end: %f", GetEngineTime(), cooldownEndTime);
	if (GetEngineTime() < cooldownEndTime)
	{
		FormatEx(rejectPhrase, maxlen, "Played recently", campaign);
		return false;
	}

	for (int i = 0; i < sizeof(g_Nomination); i++)
	{
		if (StrEqual(g_Nomination[i], campaign))
		{
			FormatEx(rejectPhrase, maxlen, "Already nominated", campaign);
			return false;
		}
	}

	if (g_RtvStatus == RTV_VOTE_ONGOING)
	{
		for (int i = 0; i < sizeof(g_Choices); i++)
		{
			if (StrEqual(g_Choices[i].campaign, campaign))
			{
				FormatEx(rejectPhrase, maxlen, "Already nominated", campaign);
				return false;
			}
		}
	}

	return true;
}

void Event_VoteChanged()
{
	Event event2 = CreateEvent("vote_changed");
	event2.SetInt("potentialVotes", 128);

	event2.SetInt("vote_option1", g_Choices[0].votes);
	event2.SetInt("vote_option2", g_Choices[1].votes);
	event2.SetInt("vote_option3", g_Choices[2].votes);
	event2.SetInt("vote_option4", g_Choices[3].votes);
	event2.SetInt("vote_option5", g_Choices[4].votes);
	event2.Fire();
}

void EndRtvVote()
{
	delete endRtvtimer;

	Event_VoteChanged();

	int maxVotesIndex = -1;
	for (int i = 0; i < g_NumRtvOptions; i++)
	{
		if (g_Choices[i].vetoed) {
			continue;
		}

		if (maxVotesIndex == -1 || g_Choices[i].votes > g_Choices[maxVotesIndex].votes)
		{
			maxVotesIndex = i;
		}
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
		{
			continue;
		}

		char buffer[255];

		if (maxVotesIndex == -1 || StrEqual(g_Choices[maxVotesIndex].campaign, "__nochange__"))
		{
			Format(buffer, sizeof(buffer), "%T\n\n\n\n\n", "Current Map Continues", client);
		}
		else 
		{
			CampaignToDisplayName(g_Choices[maxVotesIndex].campaign, buffer, sizeof(buffer), client);
			Format(buffer, sizeof(buffer), "%T\n\n\n\n\n", "Changing Level To", client, buffer);
		}

		Handle	msg = StartMessageOne("VotePass", client, USERMSG_RELIABLE);
		BfWrite bf	= UserMessageToBfWrite(msg);
		bf.WriteByte(0);
		bf.WriteString("#SDK_Chat_All");
		bf.WriteString(buffer);
		EndMessage();
	}

	if (maxVotesIndex != -1)
	{
		cvNextCampaign.SetString(g_Choices[maxVotesIndex].campaign);
		CreateTimer(5.0, Timer_ChangeToNextCampaign, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	// Clear any leftover votes
	for (int i = 0; i < sizeof(g_Choices); i++)
	{
		g_Choices[i].Clear();
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		g_Voted[i] = -1;
	}

	g_NumRtvOptions = 0;
	g_RtvStatus		= RTV_DISABLED;
}

Action Timer_ChangeToNextCampaign(Handle timer)
{
	ChangeToNextCampaign("RTV");
	return Plugin_Stop;
}

void ChangeToNextCampaign(const char[] reason = "")
{
	char nextCampaign[MAX_CAMPAIGN_LEN];
	cvNextCampaign.GetString(nextCampaign, sizeof(nextCampaign));

	if (!nextCampaign[0])
	{
		LogError("Can't change to next campaign, no next campaign is set");
		return;
	}

	char mapName[PLATFORM_MAX_PATH];
	DeserializeCampaign(nextCampaign, mapName, sizeof(mapName));
	ForceChangeLevel(mapName, reason);
}

void GetRtvRatio(int& issued, int& wanted)
{
	float wantedRatio = 0.5;

	int	  total;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			if (g_WantsChange[client])
			{
				issued++;
			}
			total++;
		}
	}

	wanted = RoundToCeil(wantedRatio * total);
}


void OverrideMapcycleStringTable()
{
	int stringTableIndex = FindStringTable("ServerMapCycle");
	int stringIndex		 = FindStringIndex(stringTableIndex, "ServerMapCycle");

	// Maplist resets every map
	int length			 = GetStringTableDataLength(stringTableIndex, stringIndex);
	char[] mapData		 = new char[length];
	GetStringTableData(stringTableIndex, stringIndex, mapData, length);

	// We'll get an extra blank entry if we don't do this
	TrimString(mapData);

	char data[4092];

	int	 maxCampaigns = g_CampaignsArray.Length;

	char campaign[PLATFORM_MAX_PATH];
	char display[255];
	char callvoteKey[256];

	for (int i = 0; i < maxCampaigns; i++)
	{
		g_CampaignsArray.GetString(i, campaign, sizeof(campaign));
		CampaignToDisplayName(campaign, display, sizeof(display), LANG_SERVER);

		strcopy(callvoteKey, sizeof(callvoteKey), display);
		ReplaceString(callvoteKey, sizeof(callvoteKey), " ", "");

		g_CallvoteKeys.SetString(callvoteKey, campaign);
		Format(data, sizeof(data), "%s\n%s", data, display);
	}

	SetStringTableData(stringTableIndex, stringIndex, data, sizeof(data));
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] args)
{
	if (StrEqual(args, "rtv", false) || StrEqual(args, "rockthevote", false) || StrEqual(args, "cambiar", false))
	{
		FakeClientCommand(client, "say /rtv");
	}
	else if (StrEqual(args, "nominate", false) || StrEqual(args, "nominar", false))
	{
		FakeClientCommand(client, "say /nominate");
	}
	else if (StrEqual(args, "nortv", false) || StrEqual(args, "nocambiar", false))
	{
		FakeClientCommand(client, "say /nortv");
	}
	else if (StrEqual(args, "currentcampaign", false))
	{
		FakeClientCommand(client, "/currentcampaign");
	}
}

void RegisterMaps()
{
	g_CampaignsMap.Clear();
	g_CampaignsArray.Clear();

	char buffer[1024];
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/campaigns.cfg");

	File f = OpenFile(buffer, "r");
	if (!f)
	{
		SetFailState("Failed to load %s", buffer);
	}

	char variables[2][256];
	while (f.ReadLine(buffer, sizeof(buffer)))
	{
		TrimString(buffer);
		ExplodeString(buffer, " ", variables, sizeof(variables), sizeof(variables[]));

		SerializeCampaign(variables[0], variables[1], buffer, sizeof(buffer));

		if (!IsMapValid(variables[0]))
		{
			PrintToServer("Ignoring '%s': map not in filesystem", buffer);
			continue;
		}
		
		RegisterCampaign(buffer);
	}

	delete f;

	Call_StartForward(g_ReadyForward);
	Call_Finish();
}

void StrLower(char[] str)
{
	for (int i = 0; str[i]; i++)
	{
		str[i] = CharToLower(str[i]);
	}
}

void SerializeCampaign(const char[] mapName, const char[] modeName, char[] campaign, int campaignLen)
{
	Format(campaign, campaignLen, "%s %s", mapName, modeName);
}

void DeserializeCampaign(const char[] campaign, char[] mapName = "", int mapNameLen = 0, char[] modeName = "", int modeNameLen = 0)
{
	int idx = SplitString(campaign, " ", mapName, mapNameLen);
	if (idx == -1)
	{
		modeName[0] = 0;
		mapName[0]	= 0;
		return;
	}

	strcopy(modeName, modeNameLen, campaign[idx]);
}

void RevertChangedCvars()
{
	int			 maxCvars = g_ChangedCvars.Length;
	GamemodeCvar cvarData;
	ConVar		 cvar;

	for (int i = 0; i < maxCvars; i++)
	{
		g_ChangedCvars.GetArray(i, cvarData);

		cvar = FindConVar(cvarData.name);
		if (cvar)
		{
			cvar.SetString(cvarData.originalValue);
		}
	}

	g_ChangedCvars.Clear();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("MM_IsValidMapAndMode", Native_IsValidMapAndMode);
	CreateNative("MM_GetCurrentMode", Native_GetCurrentMode);
	CreateNative("MM_AreMapsAndModesLoaded", Native_AreMapsAndModesLoaded);
	return APLRes_Success;
}

any Native_AreMapsAndModesLoaded(Handle plugin, int numParams)
{
	return g_ConfigsLoaded;
}


any Native_IsValidMapAndMode(Handle plugin, int numParams)
{
	char mapName[PLATFORM_MAX_PATH];
	GetNativeString(1, mapName, sizeof(mapName));

	char modeName[MAX_GAMEMODE_LEN];
	GetNativeString(2, modeName, sizeof(modeName));

	char campaign[MAX_CAMPAIGN_LEN];
	SerializeCampaign(mapName, modeName, campaign, sizeof(campaign));

	return g_CampaignsMap.ContainsKey(campaign);
}

any Native_GetCurrentMode(Handle plugin, int numParams)
{
	if (!g_CurrentCampaign[0]) {
		return false;
	}

	char modeName[MAX_GAMEMODE_LEN];
	DeserializeCampaign(g_CurrentCampaign, .modeName=modeName, .modeNameLen=sizeof(modeName));
	SetNativeString(1, modeName, GetNativeCell(2));
	return true;
}

void LoadGamemode(const char[] modeName)
{
	RevertChangedCvars();

	if (!modeName[0])
	{
		return;
	}

	LogMessage("Loading gamemode '%s'", modeName);

	ArrayList cvars;
	if (!g_Gamemodes.GetValue(modeName, cvars))
	{
		return;
	}

	int			 maxCvars = cvars.Length;
	GamemodeCvar cvarData;

	ConVar		 cvar;

	for (int i = 0; i < maxCvars; i++)
	{
		cvars.GetArray(i, cvarData);

		cvar = FindConVar(cvarData.name);
		if (!cvar)
		{
			LogError("LoadGamemode: couldn't find cvar '%s'", cvarData.name);
			continue;
		}

		cvar.GetString(cvarData.originalValue, sizeof(cvarData.originalValue)); // Save old value
		cvar.SetString(cvarData.value); // Apply new value

		LogMessage("Applying gamemode cvar '%s %s'", cvarData.name, cvarData.value);

		g_ChangedCvars.PushArray(cvarData);
	}
}