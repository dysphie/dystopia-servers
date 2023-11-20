#include <sourcemod>
//#include <namecolors>
#include <sdktools>
#include <SteamWorks>
#include <morecolors>

#define NMR_MAXPLAYERS	9

#define SND_PLAYERLEAVE "events/PlayerLeaveGame.wav"
#define SND_PLAYERJOIN	"events/PlayerJoinGame.wav"

#define MINUTES_UNKNOWN	-1

public Plugin myinfo =
{
	name		= "Custom Connect Messages",
	author		= "Dysphie",
	description = "",
	version		= "1.0.0",
	url			= ""
};

ConVar cvSndVolume;

//StringMap g_CachedMinutes;

public void OnPluginStart()
{
	//g_CachedMinutes = new StringMap();

	cvSndVolume = CreateConVar("sm_connect_sound_volume", "1.0");
	LoadTranslations("connect_messages.phrases");
	HookEvent("player_connect_client", Event_Connect, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_Disconnect, EventHookMode_Pre);

	RegAdminCmd("sm_fakejoin", Cmd_FakeJoin, ADMFLAG_ROOT);
	RegAdminCmd("sm_fakespec", Cmd_FakeNoClip, ADMFLAG_ROOT);
	RegAdminCmd("sm_fakeleave", Cmd_FakeLeave, ADMFLAG_ROOT);
	RegAdminCmd("sm_fakevac", Cmd_FakeVac, ADMFLAG_ROOT);
	//RegAdminCmd("sm_testhours", Cmd_TestHours, ADMFLAG_ROOT);
}

Action Cmd_FakeVac(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_fakevac <name>");
		return Plugin_Handled;
	}
	char playerName[64];
	GetCmdArg(1, playerName, sizeof(playerName));

	CPrintToChatAll("%t (VAC banned from secure server)", "Left", playerName);
	return Plugin_Handled;
}

Action Cmd_FakeNoClip(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_fakejoin <name>");
		return Plugin_Handled;
	}

	char playerName[64];
	GetCmdArg(1, playerName, sizeof(playerName));

	CPrintToChatAll("Dysphie joined team #SDK_Team_Spectator");
	return Plugin_Handled;
}

Action Cmd_FakeJoin(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_fakejoin <name>");
		return Plugin_Handled;
	}

	char playerName[64];
	GetCmdArg(1, playerName, sizeof(playerName));

	CPrintToChatAll("%t", "Joined", playerName);
	return Plugin_Handled;
}

Action Cmd_FakeLeave(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_fakeleave <name>");
		return Plugin_Handled;
	}
	char playerName[64];
	GetCmdArg(1, playerName, sizeof(playerName));

	CPrintToChatAll("%t", "Left", playerName);
	return Plugin_Handled;
}

public void OnMapStart()
{
	PrecacheSound(SND_PLAYERLEAVE, true);
	PrecacheSound(SND_PLAYERJOIN, true);
}

// Action Cmd_TestHours(int client, int args)
// {
// 	GetPlaytime(client, "76561198118327091");
// 	return Plugin_Handled;
// }

Action Event_Connect(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;
	return Plugin_Changed;
}

public void OnClientPostAdminCheck(int client)
{
	AnnounceConnection(client);
	// char steam64[32];
	// if (GetClientAuthId(client, AuthId_SteamID64, steam64, sizeof(steam64)))
	// {
	// 	int minutes = MINUTES_UNKNOWN;
	// 	if (g_CachedMinutes.GetValue(steam64, minutes))
	// 	{
	// 		AnnounceConnection(client, minutes);
	// 	}
	// 	else
	// 	{
	// 		GetPlaytime(client, steam64);
	// 	}
	// }
	// else 
	// {
	// 	// If no auth just print the msg now
	// 	AnnounceConnection(client);
	// }
}

Action Event_Disconnect(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;

	int client				= GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client))
	{
		return Plugin_Changed;
	}

	char reason[128];
	event.GetString("reason", reason, sizeof(reason));

	char coloredName[MAX_NAME_LENGTH];
	GetClientName(client, coloredName, sizeof(coloredName));

	if (StrContains(reason, "timed out") != -1 || 
		StrContains(reason, "Steam auth ticket") != -1 ||
		StrContains(reason, "Lost connection") != -1	
	)
	{
		CPrintToChatAll("%t", "Crashed", coloredName);
	}
	else {
		CPrintToChatAll("%t", "Left", coloredName);
	}
	// 	Server event "player_disconnect", Tick 69062:
	// - "userid" = "7"
	// - "reason" = "Gummidrop timed out"
	// - "name" = "Gummidrop"
	// - "networkid" = "[U:1:203581947]"
	// - "bot" = "0"

	EmitSoundToAll(SND_PLAYERLEAVE, SOUND_FROM_LOCAL_PLAYER, .volume = cvSndVolume.FloatValue);
	return Plugin_Changed;
}

void AnnounceConnection(int client, int minutes = MINUTES_UNKNOWN)
{
	char coloredName[MAX_NAME_LENGTH];
	GetClientName(client, coloredName, sizeof(coloredName));

	if (minutes < 0)
	{
		CPrintToChatAll("%t", "Joined", coloredName);
	}
	else {
		CPrintToChatAll("%t", "Joined Hours", coloredName, minutes / 60.0);
	}

	EmitSoundToAll(SND_PLAYERJOIN, SOUND_FROM_LOCAL_PLAYER, .volume = cvSndVolume.FloatValue);
}

// void GetPlaytime(int client, const char[] steamID64)
// {
// 	char sSteamKey[64] = "9939F7CF0C74E7B2CE68F7DA1A57232D";

// 	if (!sSteamKey[0])
// 		return;

// 	DataPack data = new DataPack();
// 	data.WriteString(steamID64);
// 	data.WriteCell(GetClientSerial(client));

// 	Handle request = SteamWorks_CreateHTTPRequest(
// 		k_EHTTPMethodGET, "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?");

// 	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 10);
// 	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "key", sSteamKey);
// 	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "format", "vdf");
// 	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "appids_filter[0]", "224260");
// 	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "include_played_free_games", "1");
// 	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "steamid", steamID64);

// 	SteamWorks_SetHTTPCallbacks(request, RequestResult_GetOwnedGames);
// 	SteamWorks_SetHTTPRequestContextValue(request, data);
// 	SteamWorks_SendHTTPRequest(request);
// }

// void RequestResult_GetOwnedGames(Handle request, bool bFailure,
// 								 bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack data)
// {
// 	//PrintToServer("RequestResult_GetOwnedGames");
// 	if (!bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
// 	{
// 		delete data;
// 		delete request;
// 		return;
// 	}

// 	data.Reset();

// 	char steam64[32];
// 	data.ReadString(steam64, sizeof(steam64));
	
// 	int client = GetClientFromSerial(data.ReadCell());
// 	if (!client)
// 	{
// 		delete data;
// 		delete request;
// 		return;
// 	}

// 	int responseSize;
// 	SteamWorks_GetHTTPResponseBodySize(request, responseSize);

// 	char[] sResponse = new char[responseSize];
// 	SteamWorks_GetHTTPResponseBodyData(request, sResponse, responseSize);
// 	delete request;

// 	KeyValues kv = new KeyValues("response");
// 	kv.ImportFromString(sResponse, "response");

// 	char resultStr[2048];
// 	kv.ExportToString(resultStr, sizeof(resultStr));

// 	int minutes = MINUTES_UNKNOWN;

// 	if (kv.GetNum("game_count") >= 1 &&
// 		kv.JumpToKey("games") &&
// 		kv.JumpToKey("0"))
// 	{
// 		minutes = kv.GetNum("playtime_forever", MINUTES_UNKNOWN);
// 		//PrintToServer("Set mins to %d", minutes);
// 	}

// 	if (g_CachedMinutes.Size < 50)
// 	{
// 		g_CachedMinutes.SetValue(steam64, minutes);
// 		CreateTimer(60.0, Cache_RemoveSteamID, data);
// 	}

// 	AnnounceConnection(client, minutes);

// 	// if (kv.JumpToKey("games") && kv.GotoFirstSubKey())
// 	// {
// 	//     char sPersonaName[MAX_NAME_LENGTH];
// 	//     kv.GetString("personaname", sPersonaName, sizeof(sPersonaName));
// 	//     // Do something
// 	// }

// 	delete request;
// 	delete kv;
// }

// Action Cache_RemoveSteamID(Handle timer, DataPack data)
// {
// 	data.Reset();
// 	char steam64[32];
// 	data.ReadString(steam64, sizeof(steam64));
// 	g_CachedMinutes.Remove(steam64);
// 	delete data;

// 	return Plugin_Continue;
// }