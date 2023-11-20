#include <sourcemod>

Database g_DB;

public Plugin myinfo = {
    name        = "Database Players",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

public void OnPluginStart()
{
	RegPluginLibrary("playerdb");
	Database.Connect(DatabaseConnectResult, "storage-local");
}

void DatabaseConnectResult(Database db, const char[] error, any data)
{
	if (!db || error[0]) {
		SetFailState("Failed to connect to database: %s", error);
	}

	g_DB = db;
	CreateTables();
}

void CreateTables()
{
	char query[1024];
	g_DB.Format(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS `player` (" ...
			"`id` INTEGER PRIMARY KEY NOT NULL , " ...
			"`name` varchar(64) NOT NULL, " ...
			"`join_date` timestamp NOT NULL DEFAULT current_timestamp, " ...
			"`last_seen` timestamp NOT NULL DEFAULT current_timestamp)"
	);

	g_DB.Query(QueryResult_CreateTables, query);
}

void QueryResult_CreateTables(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		SetFailState("Failed to create player table: %s", error);
	}

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientAuthorized(i)) {
			RegisterPlayer(i);
		}
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	RegisterPlayer(client);
}

void RegisterPlayer(int client)
{
	int accountID = GetSteamAccountID(client);
	if (!accountID) {
		return;
	}

	char playerName[MAX_NAME_LENGTH];
	GetClientName(client, playerName, sizeof(playerName));

	char query[1024];
	g_DB.Format(query, sizeof(query),
		"INSERT INTO player(id,name) VALUES(%d, '%s') " ...
		"ON CONFLICT(id) DO UPDATE SET name=excluded.name, last_seen=current_timestamp;",
		accountID, playerName);

	g_DB.Query(QueryResult_RegisterPlayer, query, accountID);
}

void QueryResult_RegisterPlayer(Database db, DBResultSet results, const char[] error, int accountID)
{
	if (!db || !results || error[0])
	{
		LogError("Failed to register player with account ID %d: %s", accountID, error);
	}
}