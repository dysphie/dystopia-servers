#include <morecolors>
#include <sdktools>

#undef REQUIRE_PLUGIN
#include <namecolors>
#define REQUIRE_PLUGIN

#define ID_NADE 49
#define ID_MOLOTOV 50
#define ID_TNT 51

public Plugin myinfo = {
	name        = "Nade Stats",
	author      = "Dysphie",
	description = "",
	version     = "1.1.0",
	url         = ""
};

Database g_DB;

int g_CachedRecord;

ConVar cvRecordSnd;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	cvRecordSnd = CreateConVar("nade_stats_record_sound", "ui/demo_bookmark.wav");
	MarkNativeAsOptional("GetColoredName");
	return APLRes_Success;
}

#define NMR_MAXPLAYERS 9

public void OnPluginStart()
{
	LoadTranslations("nadestats.phrases");
	RegConsoleCmd("sm_nadetop", Cmd_NadeTop, "View top 10 for grenade kills");
	RegConsoleCmd("sm_granadatop", Cmd_NadeTop, "Ver el top de bajas con granadas");

	Database.Connect(OnDatabaseConnection, "storage-local");
	LoadTranslations("nadestats.phrases");
	HookEvent("npc_killed", OnNPCKilled);
}

Action Cmd_NadeTop(int client, int args)
{
	ShowTop10(client);
	return Plugin_Handled;
}
void OnDatabaseConnection(Database db, const char[] error, any data)
{
	if (!db || error[0])
	{
		LogError("Failed to connect to DB, nade stats won't be saved!");
		g_DB = null;
		return;
	}

	g_DB = db;

	Transaction txn = new Transaction();

	char query[512];
	g_DB.Format(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS nade_kill ( " ...
		"player_id INTEGER, " ...
		"kills INTEGER, " ...
		"nade_weaponid INTEGER);"
	);

	txn.AddQuery(query);

	g_DB.Format(query, sizeof(query), "SELECT MAX(kills) AS highest_kills FROM nade_kill;");
	txn.AddQuery(query);

	g_DB.Execute(txn, TxnSuccess_CreateTableAndCache, TxnFail_CreateTableAndCache);
}

void TxnFail_CreateTableAndCache(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Failed to create table, nade stats won't be saved! %s", error);
}

void TxnSuccess_CreateTableAndCache(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	DBResultSet records = results[1];
	if (records.FetchRow())
	{
		g_CachedRecord = records.FetchInt(0);
		PrintToServer("Cached nade record: %d", g_CachedRecord);
	}
}

// Server event "npc_killed", Tick 48381:
// - "entidx" = "33"
// - "killeridx" = "1"
// - "isturned" = "0"
// - "weaponid" = "49"
// - "npctype" = "2"

int g_NadeKills[NMR_MAXPLAYERS+1];
int g_NadeType[NMR_MAXPLAYERS+1];

void OnNPCKilled(Event event, const char[] name, bool dontBroadcast)
{
	int weaponId = event.GetInt("weaponid");
	if (!IsWeaponNade(weaponId)) {
		return;
	}

	int client = event.GetInt("killeridx");
	if (client < 1 || client > MaxClients) {
		return;
	}

	g_NadeKills[client]++;
	if (!g_NadeType[client])
	{
		g_NadeType[client] = weaponId;
		RequestFrame(Frame_Collectg_NadeKills, GetClientSerial(client));
	}
}

void Frame_Collectg_NadeKills(int clientSerial)
{
	int client = GetClientFromSerial(clientSerial);
	if (client && IsClientInGame(client))
	{
		char name[MAX_NAME_LENGTH];

		// if (GetFeatureStatus(FeatureType_Native, "GetColoredName") == FeatureStatus_Available) {
		// 	GetColoredName(client, name, sizeof(name));
		// } else {
		GetClientName(client, name, sizeof(name));
		// }

		int nadeKills = g_NadeKills[client];
		int nadeType = g_NadeType[client];

		CPrintToChatAll("%t", "Nade Stats", name, nadeKills,
			nadeType == ID_NADE ? "grenade_projectile" : "tnt_projectile");

		// Check for record
		if (nadeKills > g_CachedRecord)
		{
			CPrintToChatAll("%t", "Beat Record", name, nadeKills, g_CachedRecord);
			g_CachedRecord = nadeKills;

			char wrSound[PLATFORM_MAX_PATH];
			cvRecordSnd.GetString(wrSound, sizeof(wrSound));
			if (wrSound[0])
			{
				EmitSoundToAllFixed(wrSound);
			}
		}

		if (!g_DB)
		{
			LogMessage("No database to insert %L, kills: %d, nade type: %d", client, g_NadeKills[client], g_NadeType[client]);
		}
		else
		{
			int accountID = GetSteamAccountID(client);
			char query[256];
			g_DB.Format(query, sizeof(query),
				"INSERT INTO nade_kill (player_id, kills, nade_weaponid)" ...
				"VALUES (%d, %d, %d);", accountID, g_NadeKills[client], g_NadeType[client]);

			g_DB.Query(QueryResult_SaveNadeKill, query);
		}

		ResetNadeCounter(client);
	}
}

void QueryResult_SaveNadeKill(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_SaveNadeKill: %s", error);
	}
}
public void OnClientDisconnect(int client)
{
	ResetNadeCounter(client);
}

void ResetNadeCounter(int client)
{
	g_NadeKills[client] = 0;
	g_NadeType[client] = 0;
}

bool IsWeaponNade(int weaponID)
{
	return weaponID == ID_NADE || weaponID == ID_TNT;
}

void EmitSoundToAllFixed(const char[] sound)
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			EmitSoundToClient(i, sound, SOUND_FROM_PLAYER);
		}
	}
}

void ShowTop10(int client)
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

	g_DB.Query(QueryResult_Top10, query, GetClientSerial(client));

}

void QueryResult_Top10(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_Top10: %s", error);
	}

	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client)) {
		return;
	}

	Panel panel = new Panel();


	char buffer[255];
	FormatEx(buffer, sizeof(buffer), "%T", "Menu Title", client);

	panel.SetTitle(buffer);

	int rank = 1;

	while (results.FetchRow())
	{
		char playerName[MAX_NAME_LENGTH];
		results.FetchString(0, playerName, sizeof(playerName));

		int kills = results.FetchInt(1);

		FormatEx(buffer, sizeof(buffer), "#%d. %s      %d", rank, playerName, kills);
		panel.DrawText(buffer);
		rank++;
	}

	if (rank == 1) {
		panel.DrawText("No entries");
	}

	panel.Send(client, MenuHandler_Top10, MENU_TIME_FOREVER);
	delete panel;
}

int MenuHandler_Top10(Menu menu, MenuAction action, int param1, int param2)
{
	return 0;
}