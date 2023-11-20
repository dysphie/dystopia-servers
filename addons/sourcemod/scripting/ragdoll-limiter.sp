
#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <morecolors>

#define NMR_MAXPLAYERS 9
Database g_DB;

bool g_DisabledRagdolls[NMR_MAXPLAYERS+1];

ConVar g_ragdoll_maxcount;

public Plugin myinfo =
{
	name = "Togglable Ragdolls",
	author = "Dysphie",
	description = "Allows players to disable zombie ragdolls",
	version = "",
	url = ""
};

public void OnPluginStart()
{
	g_ragdoll_maxcount = FindConVar("g_ragdoll_maxcount");

	Database.Connect(OnDatabaseConnectResult, "storage-local");	

	LoadTranslations("ragdolls.phrases");
	RegConsoleCmd("sm_ragdolls", Cmd_ToggleRagdolls);
	RegConsoleCmd("sm_ragdoll", Cmd_ToggleRagdolls);
	RegConsoleCmd("sm_cadaveres", Cmd_ToggleRagdolls);
}

void OnDatabaseConnectResult(Database db, const char[] error, any data)
{
	if (!db) {
		SetFailState("Failed to connect to database. %s", error);
	}

	g_DB = db;

	char query[512];
	g_DB.Format(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS ragdoll_optout ( " ...
		"steam_id INTEGER NOT NULL); "
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

public void OnClientDisconnect(int client)
{
	g_DisabledRagdolls[client] = false;
}

public void OnClientPostAdminCheck(int client)
{
	int accID = GetSteamAccountID(client);
	if (!accID) {
		return;
	}	

	char query[512];
	g_DB.Format(query, sizeof(query), 
		"SELECT * FROM ragdoll_optout WHERE steam_id = %d",
		accID);

	//PrintToServer(query);
	g_DB.Query(QueryResults_GetRagdollSetting, query, GetClientSerial(client));
}

void QueryResults_GetRagdollSetting(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResults_GetRagdollSetting: %s", error);
		return;
	}

	int client = GetClientFromSerial(clientSerial);
	if (!client) {
		return;
	}

	if (results.FetchRow()) 
	{
		g_ragdoll_maxcount.ReplicateToClient(client, "0");
		g_DisabledRagdolls[client] = true;
	}
}

Action Cmd_ToggleRagdolls(int client, int args)
{
	if (g_DisabledRagdolls[client]) {
		EnableRagdolls(client);
	} else {
		DisableRagdolls(client);
	}

	return Plugin_Handled;
}

void DisableRagdolls(int client)
{
	g_DisabledRagdolls[client] = true;
	g_ragdoll_maxcount.ReplicateToClient(client, "0");

	CPrintToChat(client, "%t", "Hid Ragdolls");

	int accID = GetSteamAccountID(client);

	if (accID)
	{
		char query[512];
		g_DB.Format(query, sizeof(query), 
			"INSERT OR REPLACE INTO ragdoll_optout (steam_id) VALUES (%d)", 
			accID);

		PrintToServer(query);
		g_DB.Query(QueryResult_DisableRagdolls, query);
	}
}

void EnableRagdolls(int client)
{
	g_DisabledRagdolls[client] = false;

	CPrintToChat(client, "%t", "Unhid Ragdolls");
	char originalVal[12];
	g_ragdoll_maxcount.GetString(originalVal, sizeof(originalVal));
	g_ragdoll_maxcount.ReplicateToClient(client, originalVal);

	int accID = GetSteamAccountID(client);
	if (accID)
	{
		char query[512];
		g_DB.Format(query, sizeof(query), 
			"DELETE FROM ragdoll_optout WHERE steam_id = %d", 
			accID);

		PrintToServer(query);
		g_DB.Query(QueryResult_EnableRagdolls, query);
	}
}

void QueryResult_DisableRagdolls(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0]) {
		LogError("QueryResult_DisableRagdolls: %s", error);
	}
}

void QueryResult_EnableRagdolls(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0]) {
		LogError("QueryResult_EnableRagdolls: %s", error);
	}
}
