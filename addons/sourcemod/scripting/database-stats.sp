#include <sourcemod>
#include <morecolors>
#include <sdkhooks>
#include <sdktools>
#include <anymap>
#include <campaigns>

#define ID_NADE 49
#define ID_MOLOTOV 50
#define ID_TNT 51

#define FLT_MAX view_as<float>(0x7F7FFFFF)
#define STATE_ACTIVE 0
#define STATE_ROUND_ONGOING 3
#define GAME_NMO          0

#define NMR_MAXPLAYERS 9

#define CONTEXT_PROFILE 0
#define CONTEXT_CAMPAIGNS 1
#define CONTEXT_RANK 2
#define CONTEXT_HISTORY 3

#define STR_INT_LEN 12

#define SECONDS_IN_YEAR 31536000
#define SECONDS_IN_MONTH 2592000
#define SECONDS_IN_DAY 86400
#define SECONDS_IN_HOUR 3600
#define SECONDS_IN_MINUTE 60

float g_NextBragTime[NMR_MAXPLAYERS+1];
bool g_PreviewingReqs[NMR_MAXPLAYERS+1];


enum
{
	Mode_Casual,
	Mode_Pro,
	Mode_NoDmg,
	Mode_MAX
}

char g_DivisionSuffix[][] = {
	"casual",
	"pro",
	"nodmg"
}

char g_DivisionPhrase[][] = {
	"Division - Casual",
	"Division - Pro",
	"Division - No Dmg"
}

char g_DivisionPrimaryColor[][] = {
	"{gray}",
	"{gold}",
	"{fuchsia}"
}

char g_DivisionSecondaryColor[][] = {
	"{lightgray}",
	"{khaki}",
	"{violet}"
}

#define SND_WR "ui/demo_bookmark.wav"

public Plugin myinfo = {
	name        = "Database Stats",
	author      = "Dysphie",
	description = "",
	version     = "1.0.0",
	url         = ""
};

#define NMR_MAXPLAYERS 9

#define ROUND_ID_PENDING -1

#define ROUND_STATE_WIN 5
#define ROUND_STATE_LOSS 6

#define GAME_TYPE_OBJECTIVE 0

int g_RoundBeginTick = -1;
PlayerRoundStats g_RoundStats[NMR_MAXPLAYERS+1];
AnyMap g_OfflineRoundStats;

int g_NadeKills[NMR_MAXPLAYERS+1];
int g_NadeType[NMR_MAXPLAYERS+1];

enum struct PlayerRoundStats
{
	int kills;
	int deaths;
	int damageTaken;
	int aliveTicks;
	bool extracted;

	void Reset()
	{
		this.kills = 0;
		this.deaths = 0;
		this.damageTaken = 0;
		this.aliveTicks = 0;
		this.extracted = false;
	}
}

GlobalForward g_RecordFwd;
int g_CachedPoints;

Database g_DB;

ConVar cvInsertExtraction;
ConVar cvValidateGame;

bool g_DatabaseReady;
bool g_CampaignsReady;
bool g_PointsRegistered;

bool g_SeenInfo[NMR_MAXPLAYERS+1];

#define TIME_NONE -1.0

enum WinSort
{
	Sort_Time,
	Sort_Damage
}

enum struct RecordPreview
{
	int cursor;
	WinSort sortType;
}

enum struct MenuProps
{
	int campaignID;
	int mode;
	int targetID;
	int contextID;
}

MenuProps g_MenuProps[NMR_MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Stats_ShowLeaderboards", Native_ShowLeaderboards);
	return APLRes_Success;
}

ConVar cvForceRecordDebug;
ConVar cvPresencePct;

public void OnPluginStart()
{
	g_OfflineRoundStats = new AnyMap();

	g_RecordFwd = new GlobalForward("OnNewTimeRecord",
		ET_Ignore, Param_String, Param_String, Param_String, Param_Float, Param_Cell, Param_String, Param_Float, Param_Cell);

	cvForceRecordDebug = CreateConVar("debug_records", "0");
	cvInsertExtraction = CreateConVar("extractions_enable", "1");
	cvValidateGame = CreateConVar("extractions_validate_cfg", "1");

	LoadTranslations("stats.phrases");
	LoadTranslations("map-names.phrases");
	LoadTranslations("mode-names.phrases");

	if (MM_AreMapsAndModesLoaded())
	{
		OnCampaignsLoaded();
	}

	Database.Connect(DatabaseConnectResult, "storage-local");

	cvPresencePct = CreateConVar("sm_presence_percentage", "80", "Presence percentage to filter Pro maps by");

	RegAdminCmd("debug_player_stats", Cmd_DebugPlayerStats, ADMFLAG_ROOT);
	RegAdminCmd("debug_extraction_msg", Cmd_DebugExtractionMsg, ADMFLAG_BAN);

	RegConsoleCmd("sm_mode", Cmd_Mode, "View a players's current ranking eligibility");
	RegConsoleCmd("sm_modo", Cmd_Mode, "View a players's current ranking eligibility");
	RegConsoleCmd("sm_ext", Cmd_Extraction, "View info about a specific extraction ID");
	RegConsoleCmd("sm_extraction", Cmd_Extraction, "View info about a specific extraction ID");

	RegAdminCmd("fake_ext", Cmd_FakeExt, ADMFLAG_BAN);

	RegConsoleCmd("sm_top", Cmd_Rankings, "View a list of available leaderboards");
	RegConsoleCmd("sm_top10", Cmd_Rankings, "View a list of available leaderboards");
	RegConsoleCmd("sm_leaderboard", Cmd_Rankings, "View a list of available leaderboards");
	RegConsoleCmd("sm_lb", Cmd_Rankings, "View a list of available leaderboards");
	RegConsoleCmd("sm_leaderboards", Cmd_Rankings, "View a list of available leaderboards");

	RegConsoleCmd("sm_rank", Cmd_Rank, "View your rank based on points");
	RegConsoleCmd("sm_rango", Cmd_Rank, "View your rank based on points");
	RegConsoleCmd("sm_profile", Cmd_Profile, "View someone's profile");
	RegConsoleCmd("sm_perfil", Cmd_Profile, "View someone's profile");
	RegConsoleCmd("sm_info", Cmd_Info, "View info about the current map");
	RegConsoleCmd("sm_record", Cmd_TimeRecords, "View a list of time records for the map");
	RegConsoleCmd("sm_records", Cmd_TimeRecords, "View a list of time records for the map");
	RegConsoleCmd("sm_history", Cmd_History, "View a list of recently played campaigns by a specific player");
	RegConsoleCmd("sm_historial", Cmd_History, "View a list of recently played campaigns by a specific player");

	RegConsoleCmd("sm_time", Cmd_Time, "View the currently elapsed time and record time for the current map");
	RegConsoleCmd("sm_tiempo", Cmd_Time, "View the currently elapsed time and record time for the current map");

	RegConsoleCmd("sm_maps", Cmd_Campaigns, "View a player's completed campaigns and points earned for each");
	RegConsoleCmd("sm_mapas", Cmd_Campaigns, "View a player's completed campaigns and points earned for each");

	RegAdminCmd("sm_migrate", Cmd_Migrate, ADMFLAG_ROOT);
	RegAdminCmd("reload_points", Cmd_ReloadPoints, ADMFLAG_ROOT);

	HookEventOrFail("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEventOrFail("npc_killed", Event_NPCKilled);
	HookEventOrFail("state_change", Event_RoundStateChanged);
	HookEventOrFail("player_extracted", OnPlayerExtracted, EventHookMode_Pre);
	HookEventOrFail("player_spawn", OnPlayerSpawned);
	HookEventOrFail("player_death", OnPlayerDied);
	HookEventOrFail("nmrih_round_begin", Event_RoundBegin);
	HookEventOrFail("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);

	//CreateTimer(1.0, Timer_VisualizeStats, _, TIMER_REPEAT);
}

Action Cmd_FakeExt(int client, int args)
{
	OnExtractionRecord(Mode_NoDmg, "nmo_testmap", "runners", "Dysphie", 
						60.0, "Test", 120.0);
	OnExtractionRecord(Mode_Casual, "nmo_testmap", "runners", "Dysphie", 
						60.0, "Test", 120.0);
	OnExtractionRecord(Mode_Pro, "nmo_testmap", "runners", "Dysphie", 
						60.0, "Test", 120.0);

	return Plugin_Handled;
}

Action Cmd_Mode(int issuer, int args)
{	
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	int target = issuer;

	if (args > 0)
	{
		char cmdTarget[MAX_TARGET_LENGTH];
		GetCmdArg(1, cmdTarget, sizeof(cmdTarget));
		target = FindTarget(issuer, cmdTarget, true, false);
	}

	if (target != -1) {
		Menu_Requirements(issuer, target);
	}
	return Plugin_Handled;
}

void Menu_Requirements(int issuer, int target)
{
	g_PreviewingReqs[issuer] = true;
	int deaths = g_RoundStats[target].deaths;
	float presence = GetClientPresence(target);
	float requiredPresence = cvPresencePct.FloatValue;
	bool disabledByCvar = !cvInsertExtraction.BoolValue;
	bool authenticated = GetClientDatabaseID(target) != 0;

	bool tookNoDmg = g_RoundStats[target].damageTaken <= 0;

	bool qualifiesCasual = authenticated && !disabledByCvar;
	bool neverDied = deaths <= 0;
	bool hasEnoughPresence = presence >= requiredPresence;
	bool qualifiesPro = qualifiesCasual && neverDied && hasEnoughPresence;

	bool qualifiesNoHit = qualifiesPro && tookNoDmg;

	Panel panel = new Panel();

	SetPanelTitleFormatted(panel, "%T", "Requirements - Title", issuer, target);
	DrawPanelLineBreak(panel);

	DrawPanelTextFormatted(panel, "[%s] %T", CheckCondition(qualifiesCasual), "Requirement Section - Casual", issuer);
	DrawPanelTextFormatted(panel, "    [%s] %T", CheckCondition(authenticated), "Requirement - Steam", issuer);
	DrawPanelTextFormatted(panel, "    [%s] %T", CheckCondition(!disabledByCvar), "Requirement - Ranked Map", issuer);

	DrawPanelTextFormatted(panel, " ");
	DrawPanelTextFormatted(panel, "[%s] %T", CheckCondition(qualifiesPro), "Requirement Section - Pro", issuer);
	DrawPanelTextFormatted(panel, "    [%s] %T", CheckCondition(qualifiesCasual), "Requirement - Qualify for Casual", issuer);
	DrawPanelTextFormatted(panel, "    [%s] %T", CheckCondition(neverDied), "Requirement - No Deaths", issuer, deaths);
	DrawPanelTextFormatted(panel, "    [%s] %T", CheckCondition(hasEnoughPresence), "Requirement - Presence", issuer, requiredPresence, presence);

	DrawPanelTextFormatted(panel, " ");
	DrawPanelTextFormatted(panel, "[%s] %T", CheckCondition(qualifiesNoHit), "Requirement Section - No Hit", issuer);
	DrawPanelTextFormatted(panel, "    [%s] %T", CheckCondition(qualifiesPro), "Requirement - Qualify for Pro", issuer);
	DrawPanelTextFormatted(panel, "    [%s] %T", CheckCondition(tookNoDmg), "Requirement - No Damage", issuer);
	
	DrawPanelLineBreak(panel);
	DrawPanelExitKey(panel, issuer);

	float interval = 1.0;
	panel.Send(issuer, PanelHandler_Requirements, RoundToCeil(interval));

	DataPack data;
	CreateDataTimer(interval, Timer_Requirements, data);
	data.WriteCell(GetClientSerial(issuer));
	data.WriteCell(GetClientSerial(target));
	delete panel;
}

Action Timer_Requirements(Handle timer, DataPack data)
{
	data.Reset();

	int issuer = GetClientFromSerial(data.ReadCell());
	int target = GetClientFromSerial(data.ReadCell());

	if (!issuer || !IsClientInGame(issuer) || !g_PreviewingReqs[issuer] || !target || !IsClientInGame(target)) {
		return Plugin_Stop;
	}

	Menu_Requirements(issuer, target);
	return Plugin_Continue;
}

int PanelHandler_Requirements(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		g_PreviewingReqs[param1] = false;
	}

	return 0;
}

char[] CheckCondition(bool condition)
{
	char icon[32];
	Format(icon, sizeof(icon), condition ? "✓" : "    ");
	return icon;
}

Action Cmd_History(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	// Client is fetching data for someone else
	if (args > 0)
	{
		char partialTargetName[MAX_NAME_LENGTH];
		GetCmdArg(1, partialTargetName, sizeof(partialTargetName));
		InitiateTargetChoice(issuer, CONTEXT_HISTORY, partialTargetName);
		return Plugin_Handled;
	}

	int targetID = CmdEnsureDatabaseID(issuer);
	if (!targetID) {
		return Plugin_Handled;
	}

	Menu_History(issuer, targetID);
	return Plugin_Handled;
}

void Menu_History(int issuer, int targetID, int mode = Mode_Pro)
{
	g_MenuProps[issuer].mode = mode;
	g_MenuProps[issuer].targetID = targetID;

	Transaction txn = new Transaction();

	char query[1024];
	FormatQuery_PlayerNameFromId(g_DB, query, sizeof(query), targetID);
	txn.AddQuery(query);

	g_DB.Format(query, sizeof(query),
		"SELECT e.id, c.map_name, c.mode_name, c.points " ...
			"FROM extraction_%s e " ...
			"JOIN campaign c ON e.campaign_id = c.id " ...
			"WHERE e.player_id = %d " ...
			"ORDER BY e.date DESC " ...
			"LIMIT 50;", g_DivisionSuffix[mode], targetID);

	txn.AddQuery(query);

	g_DB.Execute(txn, QueryResult_History, TxnFail_History, GetClientSerial(issuer));
}

void TxnFail_History(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFail_History [%d]: %s", failIndex, error);
}

void QueryResult_History(Database db, int issuerSerial, int numQueries, DBResultSet[] results, any[] queryData)
{
	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	int count = 0;
	int mode = g_MenuProps[issuer].mode;

	Menu menu = new Menu(MenuHandler_History);

	DBResultSet playerData = results[0];
	DBResultSet campaignData = results[1];

	if (!playerData.FetchRow())	{
		return;
	}

	char playerName[PLATFORM_MAX_PATH];
	playerData.FetchString(0, playerName, sizeof(playerName));

	menu.SetTitle("%T", "History - Title", issuer, playerName);

	while (campaignData.FetchRow())
	{		
		if (count % 6 == 0) {
			AddMenuItemFormatted(menu, "mode", _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);
		}

		char extractionID[STR_INT_LEN];
		campaignData.FetchString(0, extractionID, sizeof(extractionID));

		char mapName[PLATFORM_MAX_PATH], modeName[MAX_GAMEMODE_LEN];
		campaignData.FetchString(1, mapName, sizeof(mapName));
		campaignData.FetchString(2, modeName, sizeof(modeName));

		TranslateIfExists(mapName, mapName, sizeof(mapName), issuer);
		TranslateIfExists(modeName, modeName, sizeof(modeName), issuer);

		int points = campaignData.FetchInt(3);

		AddMenuItemFormatted(menu, extractionID, _, "%T", "History - Row", issuer, mapName, modeName, points);

		count++;
	}

	PopulateIfEmpty(menu, issuer);

	menu.Display(issuer, MENU_TIME_FOREVER);

}

int MenuHandler_History(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			char info[STR_INT_LEN];
			menu.GetItem(selection, info, sizeof(info));

			if (StrEqual(info, "mode"))
			{
				int targetID = g_MenuProps[issuer].targetID;
				int mode = g_MenuProps[issuer].mode + 1;
				if (mode >= Mode_MAX) {
					mode = 0;
				}

				Menu_History(issuer, targetID, mode);
				return 0;
			}

			int extractionID = StringToInt(info);
			Menu_Extraction(issuer, extractionID);
		}
	}

	return 0;
}

void Event_RoundStateChanged(Event event, const char[] name, bool dontBroadcast)
{
	if (!IsRoundOnGoing()) {
		return;
	}

	int gameType = event.GetInt("game_type");
	if (gameType != GAME_TYPE_OBJECTIVE) {
		return;
	}

	int state = event.GetInt("state");
	if (state == ROUND_STATE_LOSS || state == ROUND_STATE_WIN) {
		OnRoundEnd();
	}
}

void OnRoundEnd()
{
	// Forget all the things, prepare ourselves for a new round
	FlushMemory();
}

void HookEventOrFail(const char[] name, EventHook callback, EventHookMode mode=EventHookMode_Post)
{
	if (!HookEventEx(name, callback, mode)) {
		SetFailState("Required game event '%s' not  found", name);
	}
}


Action Cmd_ReloadPoints(int issuer, int args)
{
	RegisterPoints();
	return Plugin_Handled;
}

Action Cmd_Rankings(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	Menu_Leaderboards(issuer);
	return Plugin_Handled;
}

void Menu_Leaderboards(int issuer)
{
	Menu menu = new Menu(MenuHandler_Leaderboards);

	menu.SetTitle("%T", "Leaderboards - Title", issuer);

	AddMenuItemFormatted(menu, "points", _, "%T", "Top - Most Points", issuer);
	AddMenuItemFormatted(menu, "campaigns", _, "%T", "Top - Most Completed Campaigns", issuer);
	AddMenuItemFormatted(menu, "records", _, "%T", "Top - Most Time Records", issuer);
	AddMenuItemFormatted(menu, "nades", _, "%T", "Top - Best Nade", issuer);
	AddMenuItemFormatted(menu, "collect", ITEMDRAW_DISABLED, "%T", "Top - Most Collectibles", issuer);
	menu.Display(issuer, MENU_TIME_FOREVER);
}

// TODO: Merger
void Menu_Ranks(int issuer, int targetID, int mode = Mode_Pro)
{
	g_MenuProps[issuer].targetID = targetID;
	g_MenuProps[issuer].mode = mode;

	char query[1024];
	g_DB.Format(query, sizeof(query),
		"SELECT p.name, rp.rank AS rank_points, rr.rank AS rank_records, rc.rank AS rank_completions " ...
		"FROM player p " ...
		"LEFT JOIN lb_points_%s rp on p.id = rp.player_id " ...
		"LEFT JOIN lb_records_%s rr ON p.id = rr.player_id " ...
		"LEFT JOIN lb_completions_%s rc ON p.id = rc.player_id " ...
		"WHERE p.id = %d ",
		g_DivisionSuffix[mode],
		g_DivisionSuffix[mode],
		g_DivisionSuffix[mode],
		targetID);

	g_DB.Query(QueryResult_Ranks, query, GetClientSerial(issuer));
}

void QueryResult_Ranks(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0]) {
		LogError("QueryResult_Ranks: %s", error);
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	if (!results.FetchRow()) {
		// todo show internal error
		// PrintToServer("Internal error");
		return;
	}

	char playerName[MAX_NAME_LENGTH];
	results.FetchString(0, playerName, sizeof(playerName));

	// todo title

	int rank_points = results.FetchInt(1);
	int rank_records = results.FetchInt(2);
	int rank_completions = results.FetchInt(3);

	int mode = g_MenuProps[issuer].mode;

	Menu menu = new Menu(MenuHandler_Ranks);

	menu.SetTitle("%T", "Ranks - Title", issuer, playerName);

	AddMenuItemFormatted(menu, "mode", _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);
	
	AddMenuItemFormatted(menu, "rank_points", _, "%T: #%d", "Top - Most Points", issuer, rank_points);
	AddMenuItemFormatted(menu, "rank_completions", _, "%T: #%d", "Top - Most Completed Campaigns", issuer, rank_completions);
	AddMenuItemFormatted(menu, "rank_records", _, "%T: #%d", "Top - Most Time Records", issuer, rank_records);

	menu.Display(issuer, MENU_TIME_FOREVER);
}

int MenuHandler_Ranks(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			char info[64];
			menu.GetItem(selection, info, sizeof(info));

			int targetID = g_MenuProps[issuer].targetID;
			int mode = g_MenuProps[issuer].mode;

			if (StrEqual(info, "mode"))
			{
				mode = g_MenuProps[issuer].mode + 1;
				if (mode >= Mode_MAX) {
					mode = 0;
				}

				Menu_Ranks(issuer, targetID, mode);
				return 0;
			}

			float curTime = GetGameTime();
			if (curTime < g_NextBragTime[issuer]) 
			{
				CPrintToChat(issuer, "%t", "Sharing On Cooldown");
				Menu_Ranks(issuer, targetID, mode);
				return 0;
			}

			if (StrEqual(info, "rank_points"))
			{
				Chat_PointsRank(issuer, targetID, mode);
			}
			else if (StrEqual(info, "rank_completions"))
			{
				Chat_CompletionsRank(issuer, targetID, mode);
			}
			else if (StrEqual(info, "rank_records"))
			{
				Chat_TimeRecordsRank(issuer, targetID, mode);
			}

			g_NextBragTime[issuer] = curTime + 3.0;
			Menu_Ranks(issuer, targetID, mode);
		}
	}

	return 0;
}

int MenuHandler_Leaderboards(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			char info[32];
			menu.GetItem(selection, info, sizeof(info));

			if (StrEqual(info, "points"))
			{
				Menu_MostPoints(issuer);
			}
			else if (StrEqual(info, "records"))
			{
				Menu_MostTimeRecords(issuer);
			}
			else if (StrEqual(info, "nades"))
			{
				Menu_BestNade(issuer);
			}
			else if (StrEqual(info, "campaigns"))
			{
				Menu_MostCompletedCampaigns(issuer);
			}
		}
	}

	return 0;
}

void Menu_BestNade(int issuer)
{
	char query[512];
	g_DB.Format(query, sizeof(query),
		"SELECT player.name AS player_name, MAX(nade_kill.kills) AS max_nade_kill " ...
		"FROM nade_kill " ...
		"JOIN player ON nade_kill.player_id = player.id " ...
		"GROUP BY player.id " ...
		"ORDER BY max_nade_kill DESC " ...
		"LIMIT 10; "
	);

	g_DB.Query(QueryResult_BestNade, query, GetClientSerial(issuer));
}

void QueryResult_BestNade(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_Top10: %s", error);
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	Panel panel = new Panel();
	SetPanelTitleFormatted(panel, "%T", "Best Nade - Title", issuer);

	int rank = 1;

	while (results.FetchRow())
	{
		char playerName[MAX_NAME_LENGTH];
		results.FetchString(0, playerName, sizeof(playerName));

		int kills = results.FetchInt(1);

		DrawPanelTextFormatted(panel, "%T", "Best Nade - Row", issuer, rank, playerName, kills);

		rank++; // todo: make database compute the rank not us
	}

	if (rank == 1) {
		DrawPanelTextFormatted(panel, "%T", "No Records", issuer);
	}

	DrawPanelExitBackKey(panel, issuer);
	DrawPanelExitKey(panel, issuer);

	panel.Send(issuer, MenuHandler_BestNade, MENU_TIME_FOREVER);
	delete panel;
}

int MenuHandler_BestNade(Menu menu, MenuAction action, int param1, int param2)
{
	static int ITEM_EXITBACK = 8;

	switch (action)
	{
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			if (selection == ITEM_EXITBACK)
			{
				Menu_Leaderboards(issuer);
			}
		}
	}

	return 0;
}

void Menu_MostPoints(int issuer, int mode = Mode_Pro)
{
	// PrintToServer("Menu_MostPoints %s", g_DivisionSuffix[mode]);
	g_MenuProps[issuer].mode = mode;

	char query[1024];
	g_DB.Format(query, sizeof(query), "SELECT player_id, player_name, total_points, rank FROM lb_points_%s LIMIT 10;",
		g_DivisionSuffix[mode]);
	g_DB.Query(QueryResult_MostPoints, query, GetClientSerial(issuer));
}


void Menu_MostTimeRecords(int issuer, int mode = Mode_Pro)
{
	g_MenuProps[issuer].mode = mode;

	char query[1024];
	g_DB.Format(query, sizeof(query),
		"SELECT player_id, player_name, record_count, rank FROM lb_records_%s LIMIT 10;",
		g_DivisionSuffix[mode]);

	g_DB.Query(QueryResult_MostRecords, query, GetClientSerial(issuer));
}

void Menu_MostCompletedCampaigns(int issuer, int mode = Mode_Pro)
{
	g_MenuProps[issuer].mode = mode;

	char query[1024];
	g_DB.Format(query, sizeof(query),
		"SELECT player_id, player_name, completed_campaigns, rank " ...
		"FROM lb_completions_%s LIMIT 10;", g_DivisionSuffix[mode]);

	g_DB.Query(QueryResult_Menu_MostCompletedCampaigns, query, GetClientSerial(issuer));
}

void QueryResult_Menu_MostCompletedCampaigns(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_Menu_MostCompletedCampaigns: %s", error);
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	Panel panel = new Panel();
	SetPanelTitleFormatted(panel, "%T", "Most Completed Campaigns - Title", issuer);

	int mode = g_MenuProps[issuer].mode;
	DrawPanelItemFormatted(panel, _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);

	int count = 0;
	while (results.FetchRow() && count < 10)
	{
		char targetID[STR_INT_LEN];
		results.FetchString(0, targetID, sizeof(targetID));

		char playerName[MAX_NAME_LENGTH];
		results.FetchString(1, playerName, sizeof(playerName));

		int recordCount = results.FetchInt(2);
		int rank = results.FetchInt(3);

		DrawPanelTextFormatted(panel,"%T", "Most Completed Campaigns - Row",
			issuer, rank, playerName, recordCount);

		count++;
	}

	DrawPanelExitBackKey(panel, issuer);
	DrawPanelExitKey(panel, issuer);
	panel.Send(issuer, PanelHandler_MostCompletedCampaigns, MENU_TIME_FOREVER);
	delete panel;
}


void QueryResult_MostRecords(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_MostRecords: %s", error);
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}


	Panel panel = new Panel();
	SetPanelTitleFormatted(panel, "%T", "Most Time Records - Title", issuer);

	int mode = g_MenuProps[issuer].mode;
	DrawPanelItemFormatted(panel, _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);

	int count = 0;
	while (results.FetchRow() && count < 10)
	{
		char targetID[STR_INT_LEN];
		results.FetchString(0, targetID, sizeof(targetID));

		char playerName[MAX_NAME_LENGTH];
		results.FetchString(1, playerName, sizeof(playerName));

		int recordCount = results.FetchInt(2);
		int rank = results.FetchInt(3);

		DrawPanelTextFormatted(panel, "%T", "Most Time Records - Row",
			issuer, rank, playerName, recordCount);

		count++;
	}

	DrawPanelExitBackKey(panel, issuer);
	DrawPanelExitKey(panel, issuer);
	panel.Send(issuer, PanelHandler_MostTimeRecords, MENU_TIME_FOREVER);
	delete panel;

}

void SetPanelTitleFormatted(Panel panel, char[] format, any ...)
{
	char display[255];
	VFormat(display, sizeof(display), format, 3);
	panel.SetTitle(display);
}

void DrawPanelItemFormatted(Panel panel, int style = 0, char[] format, any ...)
{
	char display[255];
	VFormat(display, sizeof(display), format, 4);
	panel.DrawItem(display, style);
}

void DrawPanelTextFormatted(Panel panel, char[] format, any ...)
{
	char display[255];
	VFormat(display, sizeof(display), format, 3);
	panel.DrawText(display);
}

void AddMenuItemFormatted(Menu menu, const char[] info, int style = 0, char[] format, any ...)
{
	char display[255];
	VFormat(display, sizeof(display), format, 5);
	menu.AddItem(info, display, style);
}

bool CmdEnsureStatsAvailable(int issuer)
{
	char gamemodeName[MAX_GAMEMODE_LEN];
	if (!MM_GetCurrentMode(gamemodeName, sizeof(gamemodeName)))
	{
		CReplyToCommand(issuer, "%t", "Stats Unavailable");
		return false;
	}

	return true;
}

Action Cmd_Time(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer) || !CmdEnsureStatsAvailable(issuer)) {
		return Plugin_Handled;
	}

	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));

	char gamemodeName[MAX_GAMEMODE_LEN];
	MM_GetCurrentMode(gamemodeName, sizeof(gamemodeName));

	Transaction txn = new Transaction();
	TxnAppend_GetTimeRecords(txn, mapName, gamemodeName);

	g_DB.Execute(txn, TxnSuccess_Time, TxnFailure_Time, GetClientSerial(issuer));
	return Plugin_Handled;
}

void TxnFailure_Time(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFailure_Time [%d]: %s", failIndex, error);
}

void TxnSuccess_Time(Database db, int issuerSerial, int numQueries, DBResultSet[] results, any[] queryData)
{
	int client = GetClientFromSerial(issuerSerial);
	if (!client || !IsClientInGame(client)) {
		return;
	}

	float elapsedTime = GetRoundElapsedTime();
	
	char strElapsed[32] = "--:--";
	if (elapsedTime != -1.0) {
		SecondsToHumanTime(elapsedTime, strElapsed, sizeof(strElapsed), false);
	}
	
	CPrintToChat(client, "%t", "Elapsed Time", strElapsed);

	for (int i = 0; i < Mode_MAX; i++)
	{
		// SELECT e.id, p.name, MIN(time), DENSE_RANK () OVER (ORDER BY MIN(time)) as rank, p.id 
		DBResultSet modeResults = results[i];
		
		float wrTime = -1.0;
		
		if (modeResults.FetchRow() && !modeResults.IsFieldNull(2)) {
			wrTime = modeResults.FetchFloat(2);
		}

		char strWrTime[32] = "--:--";

		if (wrTime != -1.0) {
			SecondsToHumanTime(wrTime, strWrTime, sizeof(strWrTime), false);
		}

		bool aheadOfWr = wrTime == -1.0 || elapsedTime < wrTime;
		float gains = elapsedTime - wrTime;
		
		char strGains[64];
		SecondsToHumanTime(gains, strGains, sizeof(strGains), false, true);
		CPrintToChat(client, "%t", "Record Difference", 
			g_DivisionPhrase[i], 
			g_DivisionPrimaryColor[i], 
			strWrTime, 
			aheadOfWr ? "{green}" : "{red}",
			strGains);
	}
}

void TxnAppend_GetTimeRecords(Transaction txn, const char[] mapName, const char[] gamemodeName)
{
	for (int i = 0; i < Mode_MAX; i++)
	{
		char query[2048];
		g_DB.Format(query, sizeof(query),
			"SELECT e.id, p.name, MIN(time), DENSE_RANK () OVER (ORDER BY MIN(time)) as rank, p.id " ...
			"FROM extraction_%s e " ...
			"INNER JOIN player p ON p.id = e.player_id " ...
			"INNER JOIN campaign c ON c.id = e.campaign_id " ...
			"WHERE c.map_name = '%s' AND c.mode_name = '%s' " ...
			"GROUP BY e.player_id, p.name " ...
			"LIMIT 10; ",
			g_DivisionSuffix[i],
			mapName, gamemodeName);
		
		txn.AddQuery(query);
	}
}

// fixme: presence is going over 100! 100.77 etc

Action Cmd_Migrate(int issuer, int args)
{
	char query[512];

	char oldName[PLATFORM_MAX_PATH], newName[PLATFORM_MAX_PATH];
	GetCmdArg(1, oldName, sizeof(oldName));
	GetCmdArg(2, newName, sizeof(newName));

	g_DB.Format(query, sizeof(query), "UPDATE campaign SET map_name = '%s' WHERE map_name = '%s'", newName, oldName);
	g_DB.Query(QueryResult_MigrateCampaign, query);

	return Plugin_Handled;
}

void QueryResult_MigrateCampaign(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_MigrateCampaign: %s", error);
		return;
	}

	LogMessage("Successfully migrated campaign");
}

Action Cmd_DebugExtractionMsg(int issuer, int args)
{
	Call_StartForward(g_RecordFwd);

	Call_PushString("Broadway");
	Call_PushString("Runners Only");
	Call_PushString("Dysphie");
	Call_PushFloat(500.0);
	Call_PushCell(true);
	Call_PushString("Kiwi");
	Call_PushFloat(480.0);
	Call_PushCell(GetCmdArgInt(1));

	Call_Finish();

	return Plugin_Handled;
}

void QueryResult_MapInfo(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || !results.FetchRow()) {
		LogError("QueryResult_MapInfo: %s", error);
		return;
	}

	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client)) {
		return;
	}

	char humanAvgTime[32] = "--:--";
	
	if (!results.IsFieldNull(0)) 
	{
		float avgTime = results.FetchFloat(0);
		SecondsToHumanTime(avgTime, humanAvgTime, sizeof(humanAvgTime), false);
	}

	char mapName[255];
	char modeName[255];

	GetCurrentMap(mapName, sizeof(mapName));
	MM_GetCurrentMode(modeName, sizeof(modeName));

	TranslateIfExists(mapName, mapName, sizeof(mapName), client);
	TranslateIfExists(modeName, modeName, sizeof(modeName), client);

	float elapsedTime = GetRoundElapsedTime();

	char humanElapsedTime[32];
	SecondsToHumanTime(elapsedTime, humanElapsedTime, sizeof(humanElapsedTime), false);

	char playerName[MAX_NAME_LENGTH];
	GetClientName(client, playerName, sizeof(playerName));

	CPrintToChat(client, "%t", "Current Campaign", mapName, modeName);
	CPrintToChat(client, "%t", "Average Time", humanAvgTime);
	CPrintToChat(client, "%t", "Map Info - Points", g_CachedPoints);
}

int GetClientDivision(int client, char[] rejectPhrase = "", int maxlen = 0)
{
	if (g_RoundStats[client].deaths > 0)
	{
		strcopy(rejectPhrase, maxlen, "Died This Round");
		return Mode_Casual;
	}

	if (GetClientPresence(client) < cvPresencePct.FloatValue)
	{
		strcopy(rejectPhrase, maxlen, "Not Enough Presence");
		return Mode_Casual;
	}

	if (!cvInsertExtraction.BoolValue)
	{
		strcopy(rejectPhrase, maxlen, "Extractions Disabled");
		return Mode_Casual;
	}

	if (!GetClientDatabaseID(client))
	{
		strcopy(rejectPhrase, maxlen, "Unauthenticated");
		return Mode_Casual;
	}

	char m[2];
	if (!MM_GetCurrentMode(m, sizeof(m))) 
	{
		strcopy(rejectPhrase, maxlen, "Unregistered Map");
		return Mode_Casual;
	}

	if (g_RoundStats[client].damageTaken == 0) {
		return Mode_NoDmg;
	}

	return Mode_Pro;
}

int GetClientDatabaseID(int client)
{
	if (!IsClientAuthorized(client)) {
		return 0;
	}

	return GetSteamAccountID(client);
}

int CmdEnsureDatabaseID(int issuer)
{
	int accID = 0;
	if (IsClientAuthorized(issuer)) {
		accID = GetSteamAccountID(issuer);
	}

	if (!accID) {
		CReplyToCommand(issuer, "%t", "Must Be Connected To Steam");
	}

	return accID;
}

Action Cmd_Profile(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	// Client is fetching data for someone else
	if (args > 0)
	{
		char partialTargetName[MAX_NAME_LENGTH];
		GetCmdArg(1, partialTargetName, sizeof(partialTargetName));
		InitiateTargetChoice(issuer, CONTEXT_PROFILE, partialTargetName);
		return Plugin_Handled;
	}

	int targetID = CmdEnsureDatabaseID(issuer);
	if (!targetID) {
		return Plugin_Handled;
	}

	Menu_Profile(issuer, targetID);
	return Plugin_Handled;
}

Action Cmd_Info(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	Chat_RoundInfo(issuer);
	return Plugin_Handled;
}

// This function allows the player to specify a target player by name or partial name
// and displays a menu to select from multiple matches if any. It invokes OnPlayerChosen
// when the player makes a choice.
void InitiateTargetChoice(int issuer, int contextID, const char[] partialTargetName)
{
	char query[1024];
	g_DB.Format(query, sizeof(query), "SELECT id, name FROM player WHERE name LIKE '%%%s%%'", partialTargetName);

	DataPack data = new DataPack();
	data.WriteCell(GetClientSerial(issuer));
	data.WriteCell(contextID);
	g_DB.Query(QueryResult_ChooseTarget, query, data);
}


void QueryResult_ChooseTarget(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_ChooseTarget: %s", error);
		return;
	}

	data.Reset();
	int issuerSerial = data.ReadCell();
	int contextID = data.ReadCell();

	//PrintToServer("context ID was %d", contextID);
	delete data;

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	if (!results.FetchRow()) {
		return;
	}

	// Single match, don't ask anything
	if (results.RowCount == 1)
	{
		int targetID = results.FetchInt(0);
		OnPlayerChosen(issuer, targetID, contextID);
		return;
	}

	Menu menu = new Menu(MenuHandler_ChooseTarget);
	menu.SetTitle("%T", "Multiple Names Match", issuer);

	g_MenuProps[issuer].contextID = contextID;

	do
	{
		char targetID[12];
		results.FetchString(0, targetID, sizeof(targetID));

		char playerName[MAX_NAME_LENGTH];
		results.FetchString(1, playerName, sizeof(playerName));

		menu.AddItem(targetID, playerName);
	}
	while (results.FetchRow());

	menu.Display(issuer, MENU_TIME_FOREVER);
}

int MenuHandler_ChooseTarget(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			char info[12];
			menu.GetItem(selection, info, sizeof(info));
			int targetID = StringToInt(info);
			int contextID = g_MenuProps[issuer].contextID;
			OnPlayerChosen(issuer, targetID, contextID);
		}
	}

	return 0;
}

void OnPlayerChosen(int issuer, int targetID, int context)
{
	// char contextNames[][] = {
	// 	"CONTEXT_PROFILE",
	// 	"CONTEXT_CAMPAIGNS",
	// 	"CONTEXT_RANK"
	// }

	// PrintToServer("OnPlayerChosen %d -> %s", targetID, contextNames[context]);

	switch (context)
	{
		case CONTEXT_PROFILE:
		{
			Menu_Profile(issuer, targetID);
		}
		case CONTEXT_CAMPAIGNS:
		{
			//PrintToServer("CONTEXT IS CAMPAIGNS");
			Menu_Campaigns(issuer, targetID, Mode_Pro);
		}
		case CONTEXT_RANK:
		{
			Menu_Ranks(issuer, targetID);
		}
		case CONTEXT_HISTORY:
		{
			Menu_History(issuer, targetID);
		}
	}
}

Action Cmd_Rank(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	if (args > 0)
	{
		char partialTargetName[MAX_NAME_LENGTH];
		GetCmdArg(1, partialTargetName, sizeof(partialTargetName));
		InitiateTargetChoice(issuer, CONTEXT_RANK, partialTargetName);
		return Plugin_Handled;
	}

	int targetID = CmdEnsureDatabaseID(issuer);
	if (!targetID) {
		return Plugin_Handled;
	}

	Menu_Ranks(issuer, targetID);
	return Plugin_Handled;
}

void Chat_PointsRank(int issuer, int targetID, int mode)
{
	char query[256];
	g_DB.Format(query, sizeof(query),
		"SELECT p.name, rp.rank, rp.total_points, rp.rankup_points " ...
		"FROM player p " ...
		"LEFT JOIN lb_points_%s rp ON rp.player_id = p.id " ...
		"WHERE id = %d;",
		g_DivisionSuffix[mode], targetID);

	g_DB.Query(QueryResult_PointsRank, query, GetClientSerial(issuer));
}

void Chat_CompletionsRank(int issuer, int targetID, int mode)
{
	char query[256];
	g_DB.Format(query, sizeof(query),
		"SELECT p.name, rp.rank, rp.completed_campaigns, " ...
		"(SELECT COUNT(*) FROM campaign WHERE enabled = 1) AS total_campaigns " ...
		"FROM player p " ...
		"LEFT JOIN lb_completions_%s rp ON rp.player_id = p.id " ...
		"WHERE id = %d;",
		g_DivisionSuffix[mode], targetID);

	g_DB.Query(QueryResult_CompletionsRank, query, GetClientSerial(issuer));
}

void Chat_TimeRecordsRank(int issuer, int targetID, int mode)
{
	char query[256];
	g_DB.Format(query, sizeof(query),
		"SELECT p.name, rp.rank, rp.record_count " ...
		"FROM player p " ...
		"LEFT JOIN lb_records_%s rp ON rp.player_id = p.id " ...
		"WHERE id = %d;",
		g_DivisionSuffix[mode], targetID);

	g_DB.Query(QueryResult_TimeRecordsRank, query, GetClientSerial(issuer));
}

void TxnFail_Campaigns(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFail_Campaigns [%d] : %s", failIndex, error);
}

void TxnSuccess_Campaigns(Database db, int issuerSerial, int numQueries, DBResultSet[] results, any[] queryData)
{
	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	Menu menu = new Menu(MenuHandler_Campaigns, MenuAction_Cancel);

	DBResultSet playerData = results[0];
	if (!playerData.FetchRow())	{
		return;
	}

	char playerName[PLATFORM_MAX_PATH];
	results[0].FetchString(0, playerName, sizeof(playerName));

	DBResultSet wins = results[1];

	int numAvailable; int numBeaten;
	int count = 0;

	int mode = g_MenuProps[issuer].mode;

	while (wins.FetchRow())
	{
		// if (count % 6 == 0) {
		// 	AddMenuItemFormatted(menu, "mode", _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);
		// }

		numAvailable++;

		char campaignID[12];
		wins.FetchString(0, campaignID, sizeof(campaignID));

		char mapName[255]; char modeName[255];
		wins.FetchString(1, mapName, sizeof(mapName));
		wins.FetchString(2, modeName, sizeof(modeName));

		TranslateIfExists(mapName, mapName, sizeof(mapName), issuer);
		TranslateIfExists(modeName, modeName, sizeof(modeName), issuer);

		int timesBeaten = wins.FetchInt(3);
		int basePoints = wins.FetchInt(4);

		int itemStyle = ITEMDRAW_DEFAULT;
		if (timesBeaten <= 0) {
			itemStyle = ITEMDRAW_DISABLED;
		} else {
			numBeaten++;
		}

		AddMenuItemFormatted(menu, campaignID, itemStyle, "%T", "Campaigns - Row",
			issuer, mapName, modeName, timesBeaten, basePoints);
		count++;
	}

	float pct = (numBeaten / float(numAvailable)) * 100;

	menu.SetTitle("%T", "Campaigns - Title", issuer, playerName, numBeaten, numAvailable, pct, g_DivisionPhrase[mode]);
	menu.ExitBackButton = true;
	menu.Display(issuer, MENU_TIME_FOREVER);
}


int MenuHandler_Campaigns(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			char info[12];
			menu.GetItem(selection, info, sizeof(info));

			if (StrEqual(info, "mode"))
			{
				int targetID = g_MenuProps[issuer].targetID;
				int mode = g_MenuProps[issuer].mode + 1;
				if (mode >= Mode_MAX) {
					mode = 0;
				}

				Menu_Campaigns(issuer, targetID, mode);
				return 0;
			}

			int campaignID = StringToInt(info);
			int targetID = g_MenuProps[issuer].targetID;
			int mode = g_MenuProps[issuer].mode;
			Menu_CampaignExtractions(issuer, targetID, campaignID, mode);
		}

		case MenuAction_Cancel:
		{
			int issuer = param1;
			int cancelReason = param2;

			if (cancelReason == MenuCancel_ExitBack)
			{
				int targetID = g_MenuProps[issuer].targetID;
				Menu_Profile(param1, targetID);
			}
		}
	}

	return 0;
}

void QueryResult_TimeRecordsRank(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_PointsRank: %s", error);
		return;
	}

	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (!results.FetchRow()) {
		return;
	}

	char name[MAX_NAME_LENGTH];
	results.FetchString(0, name, sizeof(name));
	int rank = results.FetchInt(1);
	int mode = g_MenuProps[client].mode;

	if (results.IsFieldNull(1)) 
	{
		CPrintToChatAll("%t", "Announce Time Records Unranked", name, g_DivisionPrimaryColor[mode], g_DivisionPhrase[mode]);
		return;
	}

	int numTimeRecords = results.FetchInt(2);

	CPrintToChatAll("%t", "Announce Time Records Rank",
		name, rank, numTimeRecords, g_DivisionPrimaryColor[mode], g_DivisionPhrase[mode]);
}


void QueryResult_CompletionsRank(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_PointsRank: %s", error);
		return;
	}

	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (!results.FetchRow())
	{
		// TODO: Print client is unranked
		return;
	}

	char name[MAX_NAME_LENGTH];
	results.FetchString(0, name, sizeof(name));

	int rank = results.FetchInt(1);
	int mode = g_MenuProps[client].mode;

	if (results.IsFieldNull(1)) 
	{
		CPrintToChatAll("%t", "Announce Completions Unranked", name, g_DivisionPrimaryColor[mode], g_DivisionPhrase[mode]);
		return;
	}

	int numCompletions = results.FetchInt(2);
	int totalCampaigns = results.FetchInt(3);
	float pct = numCompletions * 100.0 / totalCampaigns;

	CPrintToChatAll("%t", "Announce Completions Rank", name, rank, pct, g_DivisionPrimaryColor[mode], g_DivisionPhrase[mode]);
}

void QueryResult_PointsRank(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_PointsRank: %s", error);
		return;
	}

	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	if (!results.FetchRow())
	{
		// TODO: Print client is unranked
		return;
	}

	// name, rank, total_points, rankup_points
	char name[MAX_NAME_LENGTH];
	results.FetchString(0, name, sizeof(name));

	int mode = g_MenuProps[client].mode;

	if (results.IsFieldNull(1)) 
	{
		CPrintToChatAll("%t", "Announce Points Unranked", name, g_DivisionPrimaryColor[mode], g_DivisionPhrase[mode]);
		return;
	}

	int rank = results.FetchInt(1);
	int points = results.FetchInt(2);

	CPrintToChatAll("%t", "Announce Points Rank", name, rank, points,
		g_DivisionPrimaryColor[mode], g_DivisionPhrase[mode]);
}

void FormatQuery_PlayerNameFromId(Database db, char[] query, int maxlen, int targetID)
{
	db.Format(query, maxlen, "SELECT name FROM player WHERE id = %d LIMIT 1;", targetID);
}

void FormatQuery_CampaignNameFromId(Database db, char[] query, int maxlen, int campaignID)
{
	db.Format(query, maxlen, "SELECT map_name, mode_name FROM campaign WHERE id = %d LIMIT 1;", campaignID);
}

void Menu_CampaignExtractions(int issuer, int targetID, int campaignID, int mode = Mode_Pro) // todo allow 3rd party target
{
	if (!targetID || !campaignID)
	{
		LogError("Menu_CampaignExtractions: Invalid targetID or campaignID 0 was passed", targetID);
		return;
	}

	Transaction txn = new Transaction();

	char query[512];
	FormatQuery_PlayerNameFromId(g_DB, query, sizeof(query), targetID);
	txn.AddQuery(query);

	g_DB.Format(query, sizeof(query), "SELECT map_name, mode_name FROM campaign WHERE id = %d LIMIT 1;", campaignID);
	txn.AddQuery(query);
	// todo use mode in query view
	g_DB.Format(query, sizeof(query), "SELECT e.id, date, time, kills, damage " ...
		"FROM extraction e " ...
		"JOIN campaign c ON c.id = e.campaign_id " ...
		"WHERE c.enabled = 1 AND e.campaign_id = %d AND player_id = %d " ...
		"ORDER BY time ASC; ",
		campaignID, targetID);
	txn.AddQuery(query);

	g_MenuProps[issuer].targetID = targetID;
	g_MenuProps[issuer].campaignID = campaignID;
	g_MenuProps[issuer].mode = mode;

	g_DB.Execute(txn, TxnSuccess_CampaignExtractions, TxnFail_CampaignExtractions, GetClientSerial(issuer));
}

void TxnFail_CampaignExtractions(Database db, int clientSerial, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFail_CampaignExtractions [%d]: %s", failIndex, error);
}

void TxnSuccess_CampaignExtractions(Database db, int issuerSerial, int numQueries, DBResultSet[] results, any[] queryData)
{
	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	DBResultSet playerData = results[0];
	DBResultSet campaignData = results[1];

	if (!playerData.FetchRow())	{
		return;
	}

	char playerName[PLATFORM_MAX_PATH];
	playerData.FetchString(0, playerName, sizeof(playerName));

	if (!campaignData.FetchRow())	{
		//PrintToServer("bad campaign data");
		return;
	}

	char mapName[PLATFORM_MAX_PATH]; char modeName[MAX_GAMEMODE_LEN];
	campaignData.FetchString(0, mapName, sizeof(mapName));
	campaignData.FetchString(1, modeName, sizeof(modeName));

	TranslateIfExists(mapName, mapName, sizeof(mapName), issuer);
	TranslateIfExists(modeName, modeName, sizeof(modeName), issuer);

	Menu menu = new Menu(MenuHandler_CampaignExtractions);

	menu.SetTitle("%T\n ", "Campaign History Title", issuer, playerName, mapName, modeName);

	DBResultSet wins = results[2];

	while (wins.FetchRow())
	{
		char extractionID[STR_INT_LEN];
		wins.FetchString(0, extractionID, sizeof(extractionID));

		char date[11]; // Hack to chop off hh:mm:ss
		wins.FetchString(1, date, sizeof(date));

		float time = wins.FetchFloat(2);
		int kills = wins.FetchInt(3);
		int dmg = wins.FetchInt(4);

		char humanTime[32];
		SecondsToHumanTime(time, humanTime, sizeof(humanTime));

		AddMenuItemFormatted(menu, extractionID, _, "%T", "Campaign History Entry",
			issuer, date, humanTime, kills, dmg);
	}

	PopulateIfEmpty(menu, issuer);

	menu.ExitBackButton = true;
	menu.Display(issuer, MENU_TIME_FOREVER);
}

void PopulateIfEmpty(Menu menu, int lang)
{
	if (menu.ItemCount <= 0)
	{
		AddMenuItemFormatted(menu, "", ITEMDRAW_DISABLED, "%T", "No Records", lang);
	}
}

int MenuHandler_CampaignExtractions(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			int client = param1;
			int selection = param2;

			char info[32];
			menu.GetItem(selection, info, sizeof(info));

			int extractionID = StringToInt(info);
			Menu_Extraction(client, extractionID);
		}
		case MenuAction_Cancel:
		{
			int issuer = param1;
			int cancelReason = param2;

			if (cancelReason == MenuCancel_ExitBack)
			{
				int targetID = g_MenuProps[issuer].targetID;
				int mode = g_MenuProps[issuer].mode;

				Menu_Campaigns(issuer, targetID, mode);
			}
		}
	}
	return 0;
}

void Menu_Profile(int issuer, int targetID, int mode = Mode_Pro)
{
	g_MenuProps[issuer].targetID = targetID;
	g_MenuProps[issuer].mode = mode;

	char query[2048];
	FormatQuery_GetProfile(query, sizeof(query), targetID, mode);

	g_DB.Query(QueryResult_Profile, query, GetClientSerial(issuer));
}
void QueryResult_Profile(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_Profile: %s", error);
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	if (!results.FetchRow())
	{
		CPrintToChat(issuer, "%t", "Profile Not Ready");
		return;
	}


	// joindate, lastseen, name, totalpoints, rank, rankuppoints, completedcamps, totalplayers, totalcampaigns

	int secsSinceRegister = results.FetchInt(0);
	int secsSinceSeen = results.FetchInt(1);

	char targetName[PLATFORM_MAX_PATH];
	results.FetchString(2, targetName, sizeof(targetName));

	int pointsAmount = results.FetchInt(3);
	int rank = results.FetchInt(4);
	int rankupPoints =  results.FetchInt(5);
	int campaignsBeaten = results.FetchInt(6);
	int totalPlayers = results.FetchInt(7);
	int totalCampaigns = results.FetchInt(8);

	int mode = g_MenuProps[issuer].mode;

	Panel panel = new Panel();
	SetPanelTitleFormatted(panel, "%T", "Profile - Title", issuer, targetName);

	DrawPanelItemFormatted(panel, _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);

	DrawPanelLineBreak(panel);

	char humanJoinDate[255];
	SecondsToTimeAdverbial(secsSinceRegister, humanJoinDate, sizeof(humanJoinDate), issuer);
	DrawPanelTextFormatted(panel, "%T", "Profile - Join Date", issuer, humanJoinDate);

	char humanLastSeen[255];
	SecondsToTimeAdverbial(secsSinceSeen, humanLastSeen, sizeof(humanLastSeen), issuer);

	// TODO: We are getting just now for ppl who haven't connected in ages
	DrawPanelTextFormatted(panel, "%T", "Profile - Last Seen", issuer, humanLastSeen);

	DrawPanelLineBreak(panel);

	if (rank > 0)
	{
		DrawPanelTextFormatted(panel, "%T", "Profile - Rank", issuer, rank, totalPlayers);
		DrawPanelTextFormatted(panel, "%T", "Profile - Rank Points", issuer, pointsAmount, rankupPoints);
	}
	else
	{
		DrawPanelTextFormatted(panel, "%T", "Profile - Unranked", issuer);
	}

	DrawPanelLineBreak(panel);

	DrawPanelTextFormatted(panel, "%T", "Profile - Completion Rate", issuer,
		campaignsBeaten, totalCampaigns,
		campaignsBeaten * 100.0 / totalCampaigns
	);

	DrawPanelItemFormatted(panel, _, "%T", "Profile - View Campaigns", issuer);

	DrawPanelLineBreak(panel);
	DrawPanelExitKey(panel, issuer);

	panel.Send(issuer, PanelHandler_Profile, MENU_TIME_FOREVER);

	delete panel;
}

void DrawPanelExitKey(Panel panel, int issuer)
{
	panel.CurrentKey = 10;
	DrawPanelItemFormatted(panel, _, "%T", "Exit", issuer);
}

void DrawPanelExitBackKey(Panel panel, int issuer)
{
	panel.CurrentKey = 8;
	DrawPanelItemFormatted(panel, _, "%T", "Back", issuer);
}


void DrawPanelLineBreak(Panel panel)
{
	panel.DrawText("\n ");
}

int PanelHandler_Profile(Menu menu, MenuAction action, int param1, int param2)
{
	static int ITEM_MODE = 1;
	static int ITEM_CAMPAIGNS = 2;

	switch (action)
	{
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;
			int targetID = g_MenuProps[issuer].targetID;
			int mode = g_MenuProps[issuer].mode;

			if (selection == ITEM_MODE)
			{
				int newMode = g_MenuProps[issuer].mode + 1;
				if (newMode >= Mode_MAX) {
					newMode = 0;
				}

				Menu_Profile(issuer, targetID, newMode);
			}
			else if (selection == ITEM_CAMPAIGNS)
			{
				Menu_Campaigns(issuer, targetID, mode);
			}
		}
	}

	return 0;
}

void DatabaseConnectResult(Database db, const char[] error, any data)
{
	if (!db || error[0])
	{
		LogError("Failed to connect to DB: %s", error);
		return;
	}

	g_DB = db;
	CreateTables();
}


any Native_ShowLeaderboards(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	Menu_Leaderboards(client);
	return 0;
}

Action Cmd_Campaigns(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	// Client is fetching data for someone else
	if (args > 0)
	{
		char partialTargetName[MAX_NAME_LENGTH];
		GetCmdArg(1, partialTargetName, sizeof(partialTargetName));
		InitiateTargetChoice(issuer, CONTEXT_CAMPAIGNS, partialTargetName);
		//PrintToServer("Initiated choice with context campaign");
		return Plugin_Handled;
	}

	int targetID = CmdEnsureDatabaseID(issuer);
	if (!targetID) {
		return Plugin_Handled;
	}

	Menu_Campaigns(issuer, targetID);
	return Plugin_Handled;
}

void Menu_Campaigns(int issuer, int targetID, int mode = Mode_Pro)
{
	g_MenuProps[issuer].targetID = targetID;
	g_MenuProps[issuer].mode = mode;

	Transaction txn = new Transaction();

	char query[1024];
	FormatQuery_PlayerNameFromId(g_DB, query, sizeof(query), targetID);
	txn.AddQuery(query);

	g_DB.Format(query, sizeof(query),
		"SELECT c.id, c.map_name, c.mode_name, COUNT(e.id) as extractions, c.points, c.points * COUNT(e.id) as total_points " ...
		"FROM campaign c " ...
		"LEFT JOIN extraction_%s e ON c.id = e.campaign_id AND e.player_id = %d " ...
		"WHERE c.enabled = 1 " ...
		"GROUP BY c.id " ...
		"ORDER BY total_points DESC, c.map_name ASC;", g_DivisionSuffix[mode], targetID);
	txn.AddQuery(query);

	g_DB.Execute(txn, TxnSuccess_Campaigns, TxnFail_Campaigns, GetClientSerial(issuer));
}

public void OnMapStart()
{
	FlushMemory();
	g_CachedPoints = 0;
	PrecacheSound(SND_WR, true);
}

public void OnCampaignsLoaded()
{
	g_CampaignsReady = true;
	if (g_DatabaseReady && !g_PointsRegistered) {
		//PrintToServer("OnCampaignsLoaded: Database ready too, lets register points");
		RegisterPoints();
	}
}

void RegisterPoints()
{
	g_PointsRegistered = false;

	char buffer[1024];
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/campaigns.cfg");

	File f = OpenFile(buffer, "r");
	if (!f) {
		SetFailState("Failed to load %s", buffer);
	}

	Transaction txn = new Transaction();

	char variables[3][256];
	char query[256];


	// Disable all existing campaigns
	g_DB.Format(query, sizeof(query), "UPDATE campaign SET enabled = 0;");
	txn.AddQuery(query);

	while (f.ReadLine(buffer, sizeof(buffer)))
	{
		TrimString(buffer);
		ExplodeString(buffer, " ", variables, sizeof(variables), sizeof(variables[]));

		// fixme renable this
		if (cvValidateGame.BoolValue && !MM_IsValidMapAndMode(variables[0], variables[1]))
		{
			continue;
		}

		DataPack data = new DataPack();
		data.WriteString(buffer);

		// FIXME: We should be validating 'gamemode' before inserting
		g_DB.Format(query, sizeof(query), "INSERT INTO campaign (map_name, mode_name, points, enabled) " ...
			"VALUES ('%s', '%s', '%s', 1) " ...
			"ON CONFLICT (map_name, mode_name) DO UPDATE " ...
			"SET points = EXCLUDED.points, enabled = EXCLUDED.enabled;",
			variables[0], variables[1], variables[2]);

		txn.AddQuery(query, data);
	}

	delete f;

	g_DB.Execute(txn, TxnSuccess_InsertPoints, TxnFailure_InsertPoints);
}

void TxnSuccess_InsertPoints(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	g_PointsRegistered = true;
	CacheMMPoints();
	LogMessage("TxnSuccess_InsertPoints");
}

void TxnFailure_InsertPoints(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFailure_InsertPoints: [%d] %s", failIndex, error);
}

void QueryResult_MostPoints(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_MostPoints: %s", error);
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer))
	{
		return;
	}

	Panel panel = new Panel();
	SetPanelTitleFormatted(panel, "%T", "Most Points - Title", issuer);

	int mode = g_MenuProps[issuer].mode;
	DrawPanelItemFormatted(panel, _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);

	int count = 0;
	while (results.FetchRow() && count < 10)
	{
		char accountID[12];
		results.FetchString(0, accountID, sizeof(accountID));

		char playerName[MAX_NAME_LENGTH];
		results.FetchString(1, playerName, sizeof(playerName));

		int points = results.FetchInt(2);
		int rank = results.FetchInt(3);

		DrawPanelTextFormatted(panel, "%T", "Most Points - Row", issuer, rank, playerName, points);

		count++;
	}

	DrawPanelExitBackKey(panel, issuer);
	DrawPanelExitKey(panel, issuer);
	panel.Send(issuer, PanelHandler_MostPoints, MENU_TIME_FOREVER);
	delete panel;
}

int PanelHandler_MostPoints(Menu menu, MenuAction action, int param1, int param2)
{
	static int ITEM_MODE_SELECT = 1;
	static int ITEM_EXITBACK = 8;

	switch (action)
	{
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			if (selection == ITEM_MODE_SELECT)
			{
				int newMode =  g_MenuProps[issuer].mode + 1;
				if (newMode >= Mode_MAX) {
					newMode = 0;
				}

				//PrintToServer("%d", newMode);
				Menu_MostPoints(issuer, newMode);
			}
			else if (selection == ITEM_EXITBACK)
			{
				Menu_Leaderboards(issuer);
			}
		}
	}

	return 0;
}

int PanelHandler_MostCompletedCampaigns(Menu menu, MenuAction action, int param1, int param2)
{
	static int ITEM_MODE = 1;
	static int ITEM_EXITBACK = 8;

	switch (action)
	{
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;
			//PrintToServer("PanelHandler_MostCompletedCampaigns %d", selection);

			if (selection == ITEM_MODE)
			{
				int newMode = g_MenuProps[issuer].mode + 1;
				if (newMode >= Mode_MAX) {
					newMode = 0;
				}

				//PrintToServer("Sending new mode %d", newMode);

				Menu_MostCompletedCampaigns(issuer, newMode);
			}
			else if (selection == ITEM_EXITBACK)
			{
				Menu_Leaderboards(issuer);
			}
		}
	}

	return 0;
}

int PanelHandler_MostTimeRecords(Menu menu, MenuAction action, int param1, int param2)
{
	static int ITEM_MODE_SELECT = 1;
	static int ITEM_EXITBACK = 8;

	switch (action)
	{
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;

			if (selection == ITEM_MODE_SELECT)
			{
				int newMode =  g_MenuProps[issuer].mode + 1;
				if (newMode >= Mode_MAX) {
					newMode = 0;
				}

				Menu_MostTimeRecords(issuer, newMode);
			}
			else if (selection == ITEM_EXITBACK)
			{
				Menu_Leaderboards(issuer);
			}
		}
	}

	return 0;
}

void OnPlayerSpawned(Event event, const char[] name, bool dontBroadcast)
{
	// Ignore false-positives
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !NMRiH_IsPlayerAlive(client))
	{
		return;
	}

	if (!IsRoundOnGoing()) {
		return;
	}

	Chat_RoundInfo(client);
}

void OnPlayerDied(Event event, const char[] name, bool dontBroadcast)
{
	// Ignore false-positives
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || NMRiH_IsPlayerAlive(client))
	{
		return;
	}
}

bool NMRiH_IsPlayerAlive(int client)
{
	return IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_iPlayerState") == STATE_ACTIVE;
}

Action Cmd_DebugPlayerStats(int admin, int args)
{
	return Plugin_Handled;
}

Action Cmd_TimeRecords(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}

	char mapName[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapName, sizeof(mapName));
	
	if (mapName[0]) 
	{
		char query[1024];
		g_DB.Format(query, sizeof(query), 
			"SELECT id, map_name, mode_name FROM campaign " ...
			"WHERE map_name LIKE '%%%s%%'", mapName);
		PrintToServer("%s", query);
		g_DB.Query(QueryResult_RecordsMapSelect, query, GetClientSerial(issuer));
	}
	else
	{
		char modeName[MAX_GAMEMODE_LEN];
		GetCurrentMap(mapName, sizeof(mapName));
		MM_GetCurrentMode(modeName, sizeof(modeName));

		char query[1024];
		g_DB.Format(query, sizeof(query), 
			"SELECT id FROM campaign " ...
			"WHERE map_name = '%s' AND mode_name = '%s'", mapName, modeName);
		g_DB.Query(QueryResult_RecordsResolveCurrentMap, query, GetClientSerial(issuer));
		
	}

	//Menu_TimeRecords(issuer);
	return Plugin_Handled;
}

void QueryResult_RecordsResolveCurrentMap(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0]) 
	{
		LogError("QueryResult_RecordsResolveCurrentMap: %s", error);
		return;
	}

	if (!results.FetchRow()) {
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	int campaignID = results.FetchInt(0);
	Menu_TimeRecords(issuer, Mode_Pro, campaignID);
}

void QueryResult_RecordsMapSelect(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	PrintToServer("QueryResult_RecordsMapSelect");
	if (!db || !results || error[0]) {
		LogError("QueryResult_RecordsMapSelect: %s", error);
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}
	PrintToServer("GetClientFromSerial good");

	char campaignID[12];
	char mapName[PLATFORM_MAX_PATH];
	char modeName[MAX_GAMEMODE_LEN];

	Menu menu = new Menu(MenuHandler_SelectCampaign);

	while (results.FetchRow())
	{
		results.FetchString(0, campaignID, sizeof(campaignID));
		results.FetchString(1, mapName, sizeof(mapName));
		results.FetchString(2, modeName, sizeof(modeName));

		TranslateIfExists(mapName, mapName, sizeof(mapName), issuer);
		TranslateIfExists(modeName, modeName, sizeof(modeName), issuer);

		AddMenuItemFormatted(menu, campaignID, _, "%T", "Campaign Entry", issuer, mapName, modeName); 
	}

	PopulateIfEmpty(menu, issuer);

	g_MenuProps[issuer].campaignID = StringToInt(campaignID);
	menu.Display(issuer, MENU_TIME_FOREVER);
}

int MenuHandler_SelectCampaign(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Select:
		{
			int selection = param2;
			int issuer = param1;
			int mode = g_MenuProps[issuer].mode;

			char campaignID[12];
			menu.GetItem(selection, campaignID, sizeof(campaignID));
			Menu_TimeRecords(issuer, mode, StringToInt(campaignID));
		}
	}
	
	return 0;
}

bool CmdEnsureNoConsole(int client)
{
	if (!client) {
		CReplyToCommand(client, "In-game command only");
		return false;
	}

	return true;
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	CacheMMPoints();
}

void CreateTables()
{
	Transaction txn = new Transaction();

	char query[512];

	g_DB.Format(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS extraction (" ...
			"id INTEGER PRIMARY KEY AUTOINCREMENT , " ...
			"player_id INTEGER NOT NULL, " ...
			"campaign_id INTEGER NOT NULL, " ...
			"time FLOAT, " ...
			"presence FLOAT, " ...
			"damage INTEGER, " ...
			"kills INTEGER, " ...
			"deaths, " ...
			"date timestamp DEFAULT current_timestamp, " ...
			"style_nohit INTEGER, " ...
			"style_noshove INTEGER, " ...
			"style_ban INTEGER, " ...
			"style_lowstam INTEGER);"
			);

	txn.AddQuery(query);


	g_DB.Format(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS campaign (  " ...
			"id INTEGER PRIMARY KEY,  " ...
			"map_name TEXT NOT NULL,  " ...
			"mode_name TEXT NOT NULL,  " ...
			"enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),  " ...
			"points INTEGER NOT NULL,  " ...
			"UNIQUE (map_name, mode_name))"
	);

	txn.AddQuery(query);


	g_DB.Format(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS nade_kill ( " ...
		"player_id INTEGER, " ...
		"kills INTEGER, " ...
		"nade_weaponid INTEGER);"
	);

	txn.AddQuery(query);

	// Extractions (Pro)
	txn.AddQuery("DROP VIEW IF EXISTS extraction_pro");
	g_DB.Format(query, sizeof(query),
		"CREATE VIEW IF NOT EXISTS extraction_pro AS " ...
		"SELECT e.* FROM extraction e " ...
		"JOIN campaign c ON e.campaign_id = c.id " ...
		"WHERE c.enabled = 1 AND e.deaths = 0 AND e.presence >= %d;", cvPresencePct.IntValue
	);

	txn.AddQuery(query);


	// Extractions (Casual)
	txn.AddQuery("DROP VIEW IF EXISTS extraction_casual");
	g_DB.Format(query, sizeof(query),
		"CREATE VIEW IF NOT EXISTS extraction_casual AS " ...
		"SELECT e.* FROM extraction e " ...
		"JOIN campaign c ON e.campaign_id = c.id " ...
		"WHERE c.enabled = 1;"
	);

	txn.AddQuery(query);

	// Extractions (Pro)
	txn.AddQuery("DROP VIEW IF EXISTS extraction_nodmg");
	g_DB.Format(query, sizeof(query),
		"CREATE VIEW IF NOT EXISTS extraction_nodmg AS " ...
		"SELECT e.* FROM extraction e " ...
		"JOIN campaign c ON e.campaign_id = c.id " ...
		"WHERE c.enabled = 1 AND e.deaths = 0 AND e.presence >= %d AND e.damage == 0;", cvPresencePct.IntValue
	);

	txn.AddQuery(query);

	
	for (int i = 0; i < sizeof(g_DivisionSuffix); i++)
	{
		// Most Points 
		g_DB.Format(query, sizeof(query), "DROP VIEW IF EXISTS lb_points_%s", g_DivisionSuffix[i]);
		txn.AddQuery(query);

		g_DB.Format(query, sizeof(query),
			"CREATE VIEW IF NOT EXISTS lb_points_%s AS " ...
			"SELECT p.id AS player_id, p.name AS player_name, " ...
			"SUM(c.points) AS total_points, " ...
			"ROW_NUMBER() OVER (ORDER BY SUM(c.points) DESC) AS rank, " ...
			"LAG(SUM(c.points)) OVER (ORDER BY SUM(c.points) DESC) - SUM(c.points) + 1 AS rankup_points " ...
			"FROM player p " ...
			"JOIN extraction_%s e ON e.player_id = p.id " ...
			"JOIN campaign c ON c.id = e.campaign_id " ...
			"GROUP BY p.id, p.name " ...
			"ORDER BY rank ASC;", g_DivisionSuffix[i], g_DivisionSuffix[i]);
		txn.AddQuery(query);

		// Most Campaigns
		g_DB.Format(query, sizeof(query), "DROP VIEW IF EXISTS lb_completions_%s", g_DivisionSuffix[i]);
		txn.AddQuery(query);

		g_DB.Format(query, sizeof(query),
			"CREATE VIEW IF NOT EXISTS lb_completions_%s AS " ...
				"SELECT p.id AS player_id, p.name AS player_name, COUNT(DISTINCT e.campaign_id) as completed_campaigns, " ...
				"ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT e.campaign_id) DESC) as rank " ...
				"FROM player p " ...
				"JOIN extraction_%s e ON e.player_id = p.id " ...
				"GROUP BY p.id, p.name " ...
				"ORDER BY rank ASC;", g_DivisionSuffix[i], g_DivisionSuffix[i]);
		txn.AddQuery(query);
		
		// Most Time Records 
		g_DB.Format(query, sizeof(query), "DROP VIEW IF EXISTS lb_records_%s", g_DivisionSuffix[i]);
		txn.AddQuery(query);

		g_DB.Format(query, sizeof(query),
			"CREATE VIEW IF NOT EXISTS lb_records_%s AS " ...
			"SELECT player_id, player_name, record_count, " ...
			"DENSE_RANK() OVER (ORDER BY record_count DESC) AS rank " ...
			"FROM (" ...
				"SELECT e.player_id, p.name AS player_name, COUNT(*) AS record_count " ...
				"FROM (" ...
					"SELECT player_id, campaign_id, time, " ...
					"RANK() OVER (PARTITION BY campaign_id ORDER BY time) AS time_rank " ...
					"FROM extraction_%s" ...
				") e " ...
				"JOIN player p ON e.player_id = p.id " ...
				"WHERE time_rank = 1 " ...
				"GROUP BY e.player_id " ...
			") t " ...
			"ORDER BY record_count DESC; ", g_DivisionSuffix[i], g_DivisionSuffix[i]);
		txn.AddQuery(query);
	}


	txn.AddQuery(query);
	g_DB.Execute(txn, TxnSuccess_CreateTables, TxnFail_CreateTables);
}

void TxnSuccess_CreateTables(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	g_DatabaseReady = true;

	if (g_CampaignsReady && !g_PointsRegistered)
	{

		//PrintToServer("TxnSuccess_CreateTables: Tables created and campaigns are ready, register points");
		RegisterPoints();
	}

	LogMessage("Extractions: Created tables");
}

void TxnFail_CreateTables(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFail_CreateTables: (%d) %s ", failIndex, error);
}

void CacheMMPoints()
{
	char mapName[PLATFORM_MAX_PATH];
	char modeName[MAX_GAMEMODE_LEN];

	if (!GetCurrentMap(mapName, sizeof(mapName)) || !MM_GetCurrentMode(modeName, sizeof(modeName))) {
		return;
	}

	char query[512];
	g_DB.Format(query, sizeof(query), "SELECT points FROM campaign WHERE map_name = '%s' AND mode_name = '%s'", mapName, modeName);
	g_DB.Query(QueryResult_GetPointsForCampaign, query);
}

void QueryResult_GetPointsForCampaign(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_GetPointsForCampaign: %s", error);

		return;
	}

	if (results.FetchRow())
	{
		g_CachedPoints = results.FetchInt(0);
	}
}

void Chat_RoundInfo(int client)
{
	char modeName[MAX_GAMEMODE_LEN]; char mapName[PLATFORM_MAX_PATH];
	if (!MM_GetCurrentMode(modeName, sizeof(modeName)) || !GetCurrentMap(mapName, sizeof(mapName)))
	{
		CPrintToChat(client, "%t", "Info - Unregistered Map");
		return;
	}

	char query[512];
	g_DB.Format(query, sizeof(query),
		"SELECT AVG(extraction.time) AS avg_extraction_time " ...
		"FROM extraction " ...
		"INNER JOIN campaign ON extraction.campaign_id = campaign.id " ...
		"WHERE campaign.mode_name = '%s' AND campaign.map_name = '%s';", modeName, mapName);


	g_DB.Query(QueryResult_MapInfo, query, GetClientSerial(client));
}

bool IsPlayer(int entity)
{
	return 0 < entity <= MaxClients && IsClientInGame(entity);
}

Action OnPlayerExtracted(Event event, const char[] name, bool dontBroadcast)
{
	if (!IsRoundOnGoing() || !cvInsertExtraction.BoolValue)
	{
		//PrintToServer("OnPlayerExtracted: BAD IsRoundOnGoing");
		return Plugin_Continue;
	}

	int client = event.GetInt("player_id");
	if (!IsPlayer(client) || !IsClientInGame(client) || g_RoundStats[client].extracted) // FIXME: Base game extracts dead players, we don't want that
	{
		//PrintToServer("OnPlayerExtracted: %d, %d, %d", IsPlayer(client), IsClientInGame(client), IsPlayerAlive(client));
		return Plugin_Continue;
	}

	g_RoundStats[client].extracted = true;

	int kills = g_RoundStats[client].kills;
	int deaths = g_RoundStats[client].deaths;
	int damageTaken = g_RoundStats[client].damageTaken;

	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));

	char modeName[MAX_GAMEMODE_LEN];
	MM_GetCurrentMode(modeName, sizeof(modeName));

	float roundTime = GetRoundElapsedTime();

	char playerName[MAX_NAME_LENGTH];
	GetClientName(client, playerName, sizeof(playerName));

	char humanTime[30];
	SecondsToHumanTime(roundTime, humanTime, sizeof(humanTime), false);

	int playerMode = GetClientDivision(client);
	CPrintToChatAll("%t", "Player Extracted", playerName, humanTime, g_DivisionPrimaryColor[playerMode], g_DivisionPhrase[playerMode], g_CachedPoints);

	int accountID = GetClientDatabaseID(client);
	if (!accountID) {
		return Plugin_Continue;
	}

	int maxDiv = GetClientDivision(client);

	Transaction txn = new Transaction();

	char query[1024];
	for (int div = 0; div <= maxDiv; div++)
	{
		g_DB.Format(query, sizeof(query),
			"SELECT MIN(e.time), p.name FROM extraction_%s e " ...
			"JOIN campaign c ON c.id = e.campaign_id " ...
			"JOIN player p ON e.player_id = p.id " ...
			"WHERE c.map_name = '%s' AND c.mode_name = '%s' ", 
			g_DivisionSuffix[div],
			mapName, modeName);
		
		txn.AddQuery(query);
	}
		
	// Insert current record
	g_DB.Format(query, sizeof(query),
		"INSERT INTO extraction (player_id, time, presence, damage, kills, deaths, campaign_id) " ...
		"SELECT %d, %f, %f, %d, %d, %d, c.id FROM campaign c WHERE c.map_name = '%s' AND c.mode_name = '%s'",
		accountID, roundTime, GetClientPresence(client), damageTaken, kills, deaths , mapName, modeName
	);

	txn.AddQuery(query);

	PrintToServer("BACKUP: %s", query);

	DataPack dp = new DataPack();
	dp.WriteString(mapName);
	dp.WriteString(modeName);
	dp.WriteString(playerName);
	dp.WriteFloat(roundTime);
	dp.WriteCell(maxDiv);

	g_DB.Execute(txn, TxnSuccess_InsertExtractionCheckWR, TxnFail_InsertExtractionCheckWR, dp);
	return Plugin_Continue;
}

void TxnSuccess_InsertExtractionCheckWR(Database db, DataPack data, int numQueries, DBResultSet[] results, any[] queryData)
{
	data.Reset();

	char mapName[PLATFORM_MAX_PATH], modeName[MAX_GAMEMODE_LEN];
	char playerName[MAX_NAME_LENGTH], oldHolderName[MAX_NAME_LENGTH];

	data.ReadString(mapName, sizeof(mapName));
	data.ReadString(modeName, sizeof(modeName));
	data.ReadString(playerName, sizeof(playerName));
	float elapsedTime = data.ReadFloat();
	int maxDiv = data.ReadCell(); // division, fix

	delete data;

	for (int i = 0; i <= maxDiv; i++)
	{
		DBResultSet set = results[i];
		float wrTime = -1.0;

		if (set.FetchRow() && !set.IsFieldNull(0))
		{
			wrTime = set.FetchFloat(0);
			set.FetchString(1, oldHolderName, sizeof(oldHolderName));
		}
			
		if (wrTime == -1.0 || elapsedTime < wrTime || cvForceRecordDebug.BoolValue)
		{
			OnExtractionRecord(i, mapName, modeName, playerName, elapsedTime, oldHolderName, wrTime);
		}
	}
}

void OnExtractionRecord(int division, const char[] mapName, const char[] modeName, const char[] newHolderName, 
						float newTime, const char[] oldHolderName, float oldTime)
{
	
	PrintToServer("OnExtractionRecord(div = %d, mapName = %s modeName = %s, newHolder = %s, newTime = %f, oldHolder=%s, oldTime=%f",
		division, mapName, modeName, newHolderName, newTime, oldHolderName, oldTime);

	char transMapName[PLATFORM_MAX_PATH], transModeName[MAX_GAMEMODE_LEN];
	TranslateIfExists(mapName, transMapName, sizeof(transMapName), LANG_SERVER);
	TranslateIfExists(modeName, transModeName, sizeof(transModeName), LANG_SERVER);

	// TODO: Bugged (?) in current Sourcemod, only consumes each color token once

	// PrintToChatAll("%t", "New Map WR", newHolderName, 
	// 	g_DivisionPrimaryColor[division], 
	// 	g_DivisionSecondaryColor[division], 
	// 	g_DivisionPhrase[division]);

	// So let's do it the dumb way:

	switch (division)
	{
		case Mode_Casual:
		{
			CPrintToChatAll("%t", "New Map WR - Casual", newHolderName);
		}
		case Mode_Pro:
		{
			CPrintToChatAll("%t", "New Map WR - Pro", newHolderName);
			EmitCoolDingSound();
		}
		case Mode_NoDmg:
		{
			CPrintToChatAll("%t", "New Map WR - No Dmg", newHolderName);
			EmitCoolDingSound();
		}
	}


	Call_StartForward(g_RecordFwd);
	Call_PushString(transMapName);
	Call_PushString(transModeName);
	Call_PushString(newHolderName);
	Call_PushFloat(newTime);
	Call_PushCell(oldTime != -1.0);
	Call_PushString(oldHolderName);
	Call_PushFloat(oldTime);
	Call_PushCell(division);
	Call_Finish();
}

void TxnFail_InsertExtractionCheckWR(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFail_InsertExtractionCheckWR [%d]: %s", failIndex, error);
}

void SecondsToHumanTime(float value, char[] buffer, int maxlen, bool includeMilli = true, bool forceSign = false)
{
	bool neg = value < 0.0;
	if (neg) {
		value = -value;
	}

	int secs    = RoundToFloor(value);
	int minutes = secs / 60;
	int seconds = secs % 60;

	char sign[2];
	if (neg) {
		sign = "-";
	} else if (forceSign) {
		sign = "+";
	}

	Format(buffer, maxlen, "%s%02d:%02d", sign, minutes, seconds);

	if (includeMilli)
	{
		int milli   = RoundToFloor((value - float(secs)) * 1000);
		Format(buffer, maxlen, "%s.%03d", buffer, milli);
	}
}

void Menu_TimeRecords(int issuer, int mode = Mode_Pro, int campaignID)
{
	//PrintToServer("Menu TimeRecords %N %d", issuer, campaignID);
	g_MenuProps[issuer].mode = mode;
	g_MenuProps[issuer].campaignID = campaignID;

	int accountID = GetSteamAccountID(issuer);
	if (accountID == 0)
	{
		CReplyToCommand(issuer, "%t", "Need Steam");
		return;
	}

	char query[2048];

	Transaction txn = new Transaction();

	FormatQuery_CampaignNameFromId(g_DB, query, sizeof(query), campaignID);
	txn.AddQuery(query);

	g_DB.Format(query, sizeof(query),
		"SELECT e.id, p.name, MIN(time), DENSE_RANK () OVER (ORDER BY MIN(time)) as rank, p.id " ...
		"FROM extraction_%s e " ...
		"INNER JOIN player p ON p.id = e.player_id " ...
		"INNER JOIN campaign c ON c.id = e.campaign_id " ...
		"WHERE c.id = %d " ...
		"GROUP BY e.player_id, p.name " ...
		"LIMIT 10;",
		g_DivisionSuffix[mode], campaignID);

	txn.AddQuery(query);

	g_DB.Execute(txn, TxnSuccess_TimeRecords, TxnFail_TimeRecords, GetClientSerial(issuer));
}

void TxnFail_TimeRecords(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFail_TimeRecords [%d]: %s", failIndex, error);
}

void TxnSuccess_TimeRecords(Database db, int issuerSerial, int numQueries, DBResultSet[] results, any[] queryData)
{
	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer) {
		return;
	}

	int accountID = GetClientDatabaseID(issuer);
	if (accountID == 0) {
		return;
	}

	DBResultSet mapData = results[0];
	DBResultSet timesData = results[1];

	if (!mapData.FetchRow()) {
		return;
	}

	char mapName[PLATFORM_MAX_PATH], modeName[MAX_GAMEMODE_LEN];
	mapData.FetchString(0, mapName, sizeof(mapName));
	mapData.FetchString(1, modeName, sizeof(modeName));

	TranslateIfExists(mapName, mapName, sizeof(mapName), issuer);
	TranslateIfExists(modeName, modeName, sizeof(modeName), issuer);

	Panel panel = new Panel();
	SetPanelTitleFormatted(panel, "%T", "Time Records - Title", issuer, mapName, modeName);

	int mode = g_MenuProps[issuer].mode;
	DrawPanelItemFormatted(panel, _, "%T", "Division Selector", issuer, g_DivisionPhrase[mode]);

	char humanTime[32];
	char playerName[MAX_NAME_LENGTH];

	int numRecords = 0;
	while (timesData.FetchRow())
	{
		// e.id, p.name, MIN(time), ROW_NUMBER() OVER(ORDER BY MIN(time)), p.id

		numRecords++;
		//char extractionID[STR_INT_LEN];
		//results.FetchString(0, extractionID, sizeof(extractionID));
		timesData.FetchString(1, playerName, sizeof(playerName));
		float time = timesData.FetchFloat(2);
		int rank = timesData.FetchInt(3);

		SecondsToHumanTime(time, humanTime, sizeof(humanTime));
		DrawPanelTextFormatted(panel, "%T", "Time Records - Row", issuer, rank, playerName, humanTime);
	}

	if (numRecords <= 0) {
		DrawPanelTextFormatted(panel, "%T", "No Records", issuer);
	}

	DrawPanelExitKey(panel, issuer);
	panel.Send(issuer, PanelHandler_TimeRecords, MENU_TIME_FOREVER);
	delete panel;
}

int PanelHandler_TimeRecords(Menu menu, MenuAction action, int param1, int param2)
{
	static int ITEM_MODE_SELECT = 1;

	switch (action)
	{
		case MenuAction_Select:
		{
			int issuer = param1;
			int selection = param2;


			if (selection == ITEM_MODE_SELECT)
			{
				int newMode =  g_MenuProps[issuer].mode + 1;
				if (newMode >= Mode_MAX) {
					newMode = 0;
				}


				Menu_TimeRecords(issuer, newMode, g_MenuProps[issuer].campaignID);
			}
		}
	}

	return 0;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	int health = GetClientHealth(victim);
	int clampedDamage = RoundToCeil(damage);
	if (clampedDamage > health) {
		clampedDamage = health;
	}

	//PrintToServer("[dmg] %N: %d + %d (original: %f, prehealth: %d)", victim, g_RoundStats[victim].damageTaken, clampedDamage, damage, health);

	g_RoundStats[victim].damageTaken += clampedDamage;
	return Plugin_Continue;
}

float GetRoundElapsedTime()
{
	if (g_RoundBeginTick == -1) {
		return -1.0;
	}

	return (GetGameTickCount() - g_RoundBeginTick) * GetTickInterval();
}

bool IsRoundOnGoing()
{
	return g_RoundBeginTick != -1;
}

void TranslateIfExists(const char[] str, char[] result, int maxlen, int lang)
{
	if (TranslationPhraseExists(str)) {
		Format(result, maxlen, "%T", str, lang)
	} else {
		strcopy(result, maxlen, str);
	}
}

void SecondsToTimeAdverbial(int seconds, char[] buffer, int maxlen, int lang)
{
	if (seconds < SECONDS_IN_MINUTE)
	{
		Format(buffer, maxlen, "%T", "Just now", lang);
		return;
	}

	if (seconds < SECONDS_IN_HOUR)
	{
		// Less than an hour has passed
		int minutes = RoundToFloor(seconds / float(SECONDS_IN_MINUTE));
		Format(buffer, maxlen, "%T", "Minutes Ago", lang, minutes);
		return;
	}

	if (seconds < SECONDS_IN_DAY)
	{
		// Less than a day has passed
		int hours = RoundToFloor(seconds / float(SECONDS_IN_HOUR));
		Format(buffer, maxlen, "%T", "Hours Ago", lang, hours);
		return;
	}

	if (seconds < SECONDS_IN_MONTH)
	{
		// Less than a month has passed:
		Format(buffer, maxlen, "%T", "Days Ago", lang, RoundToFloor(seconds / float(SECONDS_IN_DAY)));
		return;
	}


	if (seconds < SECONDS_IN_YEAR)
	{
		// Less than a year has passed
		Format(buffer, maxlen, "%T", "Months Ago", lang, RoundToFloor(seconds / float(SECONDS_IN_MONTH)));
		return;
	}

	// More than a year has passed
	Format(buffer, maxlen, "%T", "Years Ago", lang, RoundToFloor(seconds / float(SECONDS_IN_YEAR)));
}

float GetClientPresence(int client)
{
	if (g_RoundBeginTick == -1) {
		return 0.0;
	}

	int totalTicks = GetGameTickCount() - g_RoundBeginTick;
	int aliveTicks = g_RoundStats[client].aliveTicks;
	return 100.0 * aliveTicks / totalTicks;
}

// bool IsPlayerExtracted(int client)
// {
// 	return g_RoundStats[client].extracted;
// }

void FlushMemory()
{
	g_RoundBeginTick = -1;
	g_OfflineRoundStats.Clear();
	for (int i = 0; i < sizeof(g_RoundStats); i++) {
		g_RoundStats[i].Reset();
	}
}

void Event_RoundBegin(Event event, const char[] name, bool dontBroadcast)
{
	OnRoundBegin();
}

void OnRoundBegin()
{
	FlushMemory();
	g_RoundBeginTick = GetGameTickCount();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			g_RoundStats[i].aliveTicks++; // OnGameFrame won't catch this tick

			if (!g_SeenInfo[i]) 
			{
				g_SeenInfo[i] = true;
				Chat_RoundInfo(i);
			}
		}
	}
}

public void OnGameFrame()
{
	if (!IsRoundOnGoing()) {
		return;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsPlayerAlive(client))
		{
			g_RoundStats[client].aliveTicks++;
		}
	}
}

public void OnClientDisconnect(int client)
{
	if (!IsClientInGame(client)) {
		return;
	}

	g_SeenInfo[client] = false;
	g_PreviewingReqs[client] = false;

	// Save stats in case this player reconnects
	g_NextBragTime[client] = 0.0;	
	ResetNadeCounter(client);

	// The client is about to receive an additional death but we won't be there to see it
	// So increase their death count here
	if (NMRiH_IsPlayerAlive(client)) 
	{
		PrintToServer("Gave %N a death %f secs into round", client, GetRoundElapsedTime());
		g_RoundStats[client].deaths++;
	}

	int accID = GetClientDatabaseID(client);
	if (accID) {
		g_OfflineRoundStats.SetArray(accID, g_RoundStats[client], sizeof(g_RoundStats[]));	
	}
	
	g_RoundStats[client].Reset();

}

void ResetNadeCounter(int client)
{
	g_NadeKills[client] = 0;
	g_NadeType[client] = 0;
}

Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!IsRoundOnGoing()) {
		//PrintToServer("Event_PlayerDeath: !IsRoundOnGoing");
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client)) {
		//PrintToServer("!client || !IsClientInGame(client) || IsPlayerAlive(client)");
		return Plugin_Continue;
	}

	g_RoundStats[client].deaths++;
	//PrintToServer("[%d] g_RoundStats[%d].deaths++;", GetGameTickCount(), client)
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
	// If the player had previously joined this round, restore their saved state

	int accID = GetClientDatabaseID(client);
	if (!accID)
	{
		LogError("GetClientAuthId was false inside OnClientPostAdminCheck");
		return;
	}

	if (g_OfflineRoundStats.GetArray(accID, g_RoundStats[client], sizeof(g_RoundStats[])))
	{
		// Erase the now-stale backup
		g_OfflineRoundStats.Remove(accID);
	}
}

Action Timer_VisualizeStats(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
		{
			VisualizeStats(client);
		}
	}

	return Plugin_Continue;
}

void VisualizeStats(int client)
{
	PlayerRoundStats stats;
	stats = g_RoundStats[client];

	char msg[255];
	char rejectPhrase[255];

	int div = GetClientDivision(client, rejectPhrase, sizeof(rejectPhrase));
	int totalTicks = GetGameTickCount() - g_RoundBeginTick;
	int aliveTicks = g_RoundStats[client].aliveTicks;

	float elapsedTime = GetRoundElapsedTime();
	char humanElapsed[32];
	SecondsToHumanTime(elapsedTime, humanElapsed, sizeof(humanElapsed));

	Format(msg, sizeof(msg),
		"Round begin tick: %d\n" ...
		"Time: %s\n" ...
		"Presence: %.2f (%d of %d)\n" ...
		"Kills: %d\n" ...
		"Deaths: %d\n" ...
		"Damage: %d\n" ...
		"Division: %s\n%s",
		g_RoundBeginTick,
		humanElapsed,
		GetClientPresence(client),
		aliveTicks, totalTicks,
		stats.kills,
		stats.deaths,
		stats.damageTaken,
		g_DivisionPhrase[div],
		rejectPhrase);

	SetHudTextParams(1.0, 0.0, 1.15, 0, 200, 0, 200, 0, 0.0, 0.0, 0.0);
	ShowHudText(client, 0, msg);
}

void Event_NPCKilled(Event event, const char[] name, bool dontBroadcast)
{
	if (!IsRoundOnGoing()) {
		return;
	}

	int killer = event.GetInt("killeridx");
	if (!IsPlayer(killer) || !IsClientInGame(killer)) {
		return;
	}

	g_RoundStats[killer].kills++;

	int weaponId = event.GetInt("weaponid");
	if (IsWeaponNade(weaponId))
	{
		g_NadeKills[killer]++;
		if (!g_NadeType[killer])
		{
			g_NadeType[killer] = weaponId;
			RequestFrame(Frame_CollectNadeKills, GetClientSerial(killer));
		}
	}
}

void Frame_CollectNadeKills(int clientSerial)
{
	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client)) {
		return;
	}

	int nadeKills = g_NadeKills[client];
	int nadeType = g_NadeType[client];


	CPrintToChatAll("%t", "Nade Stats", client, nadeKills);

	int accountID = GetClientDatabaseID(client);
	if (!accountID) {
		return;
	}

	// Check for record

	Transaction txn = new Transaction();

	DataPack data = new DataPack();
	data.WriteCell(nadeKills);
	data.WriteCell(clientSerial);

	char query[1024];
	g_DB.Format(query, sizeof(query), "SELECT MAX(kills) FROM nade_kill;");
	txn.AddQuery(query);

	g_DB.Format(query, sizeof(query),
		"INSERT INTO nade_kill (player_id, kills, nade_weaponid) " ...
		"VALUES (%d, %d, %d);", accountID, nadeKills, nadeType);
	txn.AddQuery(query);

	g_DB.Execute(txn, TxnSuccess_CheckNadeRecord, TxnFail_CheckNadeRecord, data);

	ResetNadeTracker(client);
}

void TxnFail_CheckNadeRecord(Database db, DataPack data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	delete data;
	LogError("TxnFail_CheckNadeRecord [%d]: %s", failIndex, error);
}

void TxnSuccess_CheckNadeRecord(Database db, DataPack data, int numQueries, DBResultSet[] results, any[] queryData)
{
	data.Reset();
	int nadeKills = data.ReadCell();
	int clientSerial = data.ReadCell();
	delete data;

	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client)) {
		return;
	}

	int record = 0;

	if (results[0].FetchRow())
	{
		record =  results[0].FetchInt(0);
	}

	PrintToServer("gotten: %d, record: %d", nadeKills, record);

	if (nadeKills > record)
	{
		CPrintToChatAll("%t", "Beat Record", client, nadeKills);
		EmitCoolDingSound();
	}
}

void EmitCoolDingSound()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			EmitSoundToClient(i, SND_WR, SOUND_FROM_PLAYER);
		}
	}
}

bool IsWeaponNade(int weaponID)
{
	return weaponID == ID_NADE || weaponID == ID_TNT;
}

void ResetNadeTracker(int client)
{
	g_NadeKills[client] = 0;
	g_NadeType[client] = 0;
}

Action Cmd_Extraction(int issuer, int args)
{
	if (!CmdEnsureNoConsole(issuer)) {
		return Plugin_Handled;
	}


	//PrintToServer("Cmd_Extraction %d", issuer);

	int extractionID = GetCmdArgInt(1);
	if (!extractionID)
	{
		ReplyToCommand(issuer, "Invalid extraction ID");
		return Plugin_Handled; // TODO: Print invalid ID
	}

	Menu_Extraction(issuer, extractionID);
	return Plugin_Handled;
}

void Menu_Extraction(int issuer, int extractionID, int mode = Mode_Pro)
{
	g_MenuProps[issuer].mode = mode;

	char query[512];
	FormatQuery_GetExtractionData(query, sizeof(query), extractionID);
	g_DB.Query(QueryResult_Extraction, query, GetClientSerial(issuer));
	//PrintToServer(query);
}

void QueryResult_Extraction(Database db, DBResultSet results, const char[] error, int issuerSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_Extraction: %s", error);
		return;
	}

	int issuer = GetClientFromSerial(issuerSerial);
	if (!issuer || !IsClientInGame(issuer)) {
		return;
	}

	if (!results.FetchRow()) {
		//PrintToServer("bad row");
		return; // todo print something idk
	}

	//PrintToServer("we made it");
	//e.id, p.name, c.map_name, c.mode_name, c.points, e.time, " ...
		//"e.damage, e.kills, e.deaths, e.date, e.presence " ...
		//"FROM extraction e " ...

	int extractionID = results.FetchInt(0);
	char playerName[MAX_NAME_LENGTH];
	results.FetchString(1, playerName, sizeof(playerName));

	char mapName[PLATFORM_MAX_PATH], gamemodeName[PLATFORM_MAX_PATH];
	results.FetchString(2, mapName, sizeof(mapName));
	results.FetchString(3, gamemodeName, sizeof(gamemodeName));

	TranslateIfExists(mapName, mapName, sizeof(mapName), issuer);
	TranslateIfExists(gamemodeName, gamemodeName, sizeof(gamemodeName), issuer);

	int points = results.FetchInt(4);

	float timeElapsed = results.FetchFloat(5);

	char humanTime[32];
	SecondsToHumanTime(timeElapsed, humanTime, sizeof(humanTime));

	int damage = results.FetchInt(6);

	int kills = results.FetchInt(7);
	int deaths = results.FetchInt(8);

	char date[32];
	results.FetchString(9, date, sizeof(date));

	float presence = results.FetchFloat(10);

	Panel panel = new Panel();

	DrawPanelTextFormatted(panel, "[Extraction #%d]", extractionID);

	DrawPanelLineBreak(panel);
	DrawPanelTextFormatted(panel, "Player: %s", playerName);
	DrawPanelTextFormatted(panel, "Campaign: %s, %s", mapName, gamemodeName);
	DrawPanelTextFormatted(panel, "Points: %d", points);
	DrawPanelTextFormatted(panel, "Time: %s", humanTime);
	DrawPanelTextFormatted(panel, "Score: %d - %d", kills, deaths);
	DrawPanelTextFormatted(panel, "Damage taken: %d", damage);
	DrawPanelTextFormatted(panel, "Date: %s", date);
	DrawPanelTextFormatted(panel, "Presence: %.f%%", presence);

	DrawPanelLineBreak(panel);
	DrawPanelExitKey(panel, issuer);

	panel.Send(issuer, PanelHandler_Extraction, MENU_TIME_FOREVER);
	delete panel;

}

int PanelHandler_Extraction(Menu menu, MenuAction action, int param1, int param2)
{
	return 0;
}

void FormatQuery_GetExtractionData(char[] buffer, int maxlen, int extractionID)
{
	g_DB.Format(buffer, maxlen,
		"SELECT e.id, p.name, c.map_name, c.mode_name, c.points, e.time, " ...
		"e.damage, e.kills, e.deaths, e.date, e.presence " ...
		"FROM extraction e " ...
		"JOIN player p ON e.player_id = p.id " ...
		"JOIN campaign c ON e.campaign_id = c.id " ...
		"WHERE e.id = %d",
	extractionID);
}

void FormatQuery_GetProfile(char[] buffer, int maxlen, int targetID , int mode)
{
	g_DB.Format(buffer, maxlen,
		"SELECT " ...
			"strftime('%%s', 'now') - strftime('%%s', join_date) AS seconds_since_join_date," ...
			"strftime('%%s', 'now') - strftime('%%s', last_seen) AS seconds_since_last_seen," ...
			"p.name, pt.total_points, pt.rank, pt.rankup_points, ct.completed_campaigns, " ...
			"(SELECT COUNT(*) FROM player) AS total_players, " ...
			"(SELECT COUNT(*) FROM campaign WHERE enabled = 1) AS total_campaigns " ...
		"FROM " ...
			"player p " ...
			"LEFT JOIN lb_points_%s pt " ...
				"ON pt.player_id = p.id " ...
			"LEFT JOIN lb_completions_%s ct " ...
				"ON ct.player_id = p.id " ...
		"WHERE p.id = %d;",  g_DivisionSuffix[mode], g_DivisionSuffix[mode], targetID);
}