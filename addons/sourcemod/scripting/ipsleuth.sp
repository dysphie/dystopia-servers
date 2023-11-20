#include <sourcemod>
#include <anymap>
#include <morecolors>

Database g_DB;

public Plugin myinfo = {
    name        = "Multi-Account Snooper",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

#define MAX_IPV4_LEN 16

ConVar cvDayCutoff;

public void OnPluginStart()
{
	LoadTranslations("ipsleuth.phrases");
	LoadTranslations("common.phrases");
	//RegConsoleCmd("sm_ipsearch", Cmd_IpSearch);
	Database.Connect(OnDatabaseConnectResult, "storage-local");

	RegAdminCmd("sm_accounts", Cmd_TraceByName, ADMFLAG_ROOT);
	RegAdminCmd("sm_accs", Cmd_TraceByName, ADMFLAG_ROOT);
	RegAdminCmd("sm_trace", Cmd_TraceByName, ADMFLAG_ROOT);
	RegAdminCmd("sm_cuentas", Cmd_TraceByName, ADMFLAG_ROOT);
	RegAdminCmd("sm_traceid", Cmd_TraceByID, ADMFLAG_ROOT);

	cvDayCutoff = CreateConVar("sm_ipsleuth_day_cutoff", "32000");
}

Action Cmd_TraceByID(int issuer, int args)
{	
	if (args < 1) 
	{
		ReplyToCommand(issuer, "Usage: sm_traceid <accID>");
		return Plugin_Handled;
	}

	int accID = GetCmdArgInt(1)
	PerformTrace(accID, issuer, GetCmdReplySource());
	return Plugin_Handled;
}

Action Cmd_TraceByName(int issuer, int args)
{
	char partialName[MAX_NAME_LENGTH];
	GetCmdArg(1, partialName, sizeof(partialName));

	if (!partialName[0]) return Plugin_Handled;

	char query[1024];
	g_DB.Format(query, sizeof(query),"SELECT id, name FROM player WHERE name LIKE '%%%s%%'", partialName);

	DataPack data = new DataPack();
	data.WriteString(partialName);
	data.WriteCell(EncodeCommandIssuer(issuer));
	data.WriteCell(GetCmdReplySource());
	g_DB.Query(QueryResult_PlayerNameToID, query, data);

	return Plugin_Handled;
}

int DecodeCommandIssuer(int value)
{
	if (value == -1) {
		return 0; // Console
	}

	int client =  GetClientFromSerial(value);
	if (client && IsClientInGame(client))
	{
		return client;
	}

	return -1;
}

int EncodeCommandIssuer(int issuer)
{
	if (issuer == 0) {
		return -1;
	}

	return GetClientSerial(issuer);
}


void QueryResult_PlayerNameToID(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	char partialName[MAX_NAME_LENGTH];
	data.ReadString(partialName, sizeof(partialName));

	int issuer = DecodeCommandIssuer(data.ReadCell());
	ReplySource replySrc = data.ReadCell();

	delete data;

	if (!db || !results || error[0])
	{
		LogError("Failed lookup for %s: %s", partialName, error);
		return;
	}

	int numRows = results.RowCount;

	if (numRows == 0)
	{
		ReplyToIssuer(issuer, replySrc, "%t", "No Results For Name", partialName);
		return;
	}

	if (numRows == 1)
	{
		results.FetchRow();
		int accID = results.FetchInt(0);
		PerformTrace(accID, issuer, replySrc);
		return;
	}

	// If we are the server, print to console
	if (issuer == 0)
	{
		while (results.FetchRow())
		{
			int playerID = results.FetchInt(0);

			char playerName[MAX_NAME_LENGTH];
			results.FetchString(1, playerName, sizeof(playerName));

			PrintToServer("%d. %s", playerID, playerName);
		}

		return;
	}

	// If we are a player show a menu
	Menu menu = new Menu(MenuHandler_PickTarget);
	menu.SetTitle("%T", "Menu Title", issuer, partialName);

	while (results.FetchRow())
	{
		char key[12];
		int playerID = results.FetchInt(0);
		IntToString(playerID, key, sizeof(key));

		char playerName[MAX_NAME_LENGTH];
		results.FetchString(1, playerName, sizeof(playerName));

		menu.AddItem(key, playerName);
	}

	menu.Display(issuer, MENU_TIME_FOREVER);
}

void ReplyToIssuer(int issuer, ReplySource source, char[] format, any ...)
{
	ReplySource oldSrc = GetCmdReplySource();
	SetCmdReplySource(source);

	SetGlobalTransTarget(issuer);

	char response[1024];
	VFormat(response, sizeof(response), format, 4);
	CReplyToCommand(issuer, response);

	SetCmdReplySource(oldSrc);
}

int MenuHandler_PickTarget(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Select:
		{
			char key[12];
			menu.GetItem(param2, key, sizeof(key));

			int accID = StringToInt(key);

			PerformTrace(accID, param1, SM_REPLY_TO_CHAT);
		}
	}
	
	return 0;
}


void PerformTrace(int accID, int issuer, ReplySource replySrc)
{
	Transaction txn = new Transaction();
	char query[512];

	// Get the main account name
	g_DB.Format(query, sizeof(query), "SELECT name FROM player WHERE id = %d ", accID);
	txn.AddQuery(query);

	// PrintToServer(query);

	// Get the names of any alt accounts wefind

	g_DB.Format(query, sizeof(query), 
		"SELECT p.id, p.name " ...
		"FROM player p " ...
		"JOIN iplogs i ON i.player_id = p.id " ...
		"WHERE i.ip IN ( " ...
		"SELECT ip FROM iplogs WHERE player_id = %d AND date >= date('now', '-%d days') " ...
		") " ...
		"AND p.id != %d " ...
		"GROUP BY p.id; ",
		accID, cvDayCutoff.IntValue, accID);
	txn.AddQuery(query);


	// PrintToServer(query);
	
	DataPack replyData = new DataPack();
	replyData.WriteCell(EncodeCommandIssuer(issuer));
	replyData.WriteCell(replySrc);

	g_DB.Execute(txn, TxnSuccess_PerformTrace, TxnFail_PerformTrace, replyData);
}

void TxnSuccess_PerformTrace(Database db, DataPack replyData, int numQueries, DBResultSet[] results, any[] queryData)
{
	replyData.Reset();
	int encodedIssuer = replyData.ReadCell();
	ReplySource replySrc = replyData.ReadCell();
	delete replyData;

	int issuer = DecodeCommandIssuer(encodedIssuer);
	if (issuer == -1) {
		return;
	}

	char targetName[MAX_NAME_LENGTH];

	if (results[0].RowCount <= 0)
	{
		ReplyToIssuer(issuer, replySrc, "No account with the given ID was found");
		return;
	} 

	DBResultSet mainAccountResults = results[0];
	DBResultSet altAccountResults = results[1];

	// Get the main account's name
	mainAccountResults.FetchRow();
	mainAccountResults.FetchString(0, targetName, sizeof(targetName));

	// Get the alt accounts' names
	char humanList[255];

	// if (issuer && !CheckCommandAccess(issuer, "see_alt_names", ADMFLAG_ROOT))
	// {
	// 	IntToString(altAccountResults.RowCount, humanList, sizeof(humanList));
	// }
	// else
	// {
	int numRows = 0;
	while (altAccountResults.FetchRow())
	{
		char playerName[MAX_NAME_LENGTH];
		altAccountResults.FetchString(1, playerName, sizeof(playerName));

		if (numRows == 0) {
			Format(humanList, sizeof(humanList), "%T", "Account Name", issuer, playerName);
		}
		else {
			Format(humanList, sizeof(humanList), "%s, %T", humanList, "Account Name", issuer, playerName);
		}

		numRows++;
	}

	// }
	
	//IntToString(altAccountResults.RowCount, humanList, sizeof(humanList));

	ReplyToIssuer(issuer, replySrc, "%T", "Potential Accounts", issuer, targetName, humanList);
	ReplyToIssuer(issuer, replySrc, "%T", "Disclaimer", issuer, cvDayCutoff.IntValue);
}

void TxnFail_PerformTrace(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("TxnFail_PerformTrace: [%d] %s", failIndex, error);
}

void OnDatabaseConnectResult(Database db, const char[] error, any data)
{
	if (!db || error[0]) {
		SetFailState("Faild to connect to DB: %s", error);
	}

	g_DB = db;

	char query[1024];
	g_DB.Format(query, sizeof(query), 
		"CREATE TABLE IF NOT EXISTS iplogs (" ...
		"ip VARCHAR(16) NOT NULL, " ... 
		"player_id INTEGER NOT NULL, " ...
		"date timestamp NOT NULL DEFAULT current_timestamp, " ...
		"UNIQUE(ip,player_id));");

	g_DB.Query(CreateTablesResult, query);
}

void CreateTablesResult(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || error[0]) {
		SetFailState("Failed to create required tables, %s", error);
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	char ip[32];
	GetClientIP(client, ip ,sizeof(ip));

	int accountID = GetSteamAccountID(client);

	char query[1024];
	g_DB.Format(query, sizeof(query), 
		"INSERT INTO iplogs (ip, player_id) VALUES ('%s', %d) " ...
		"ON CONFLICT (ip, player_id) DO UPDATE SET date = current_timestamp;", 
    ip, accountID);
	g_DB.Query(DatabaseSaveIPResult, query);
}

void DatabaseSaveIPResult(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || error[0]) {
		LogError("Failed to save IP: %s", error);
	}
}