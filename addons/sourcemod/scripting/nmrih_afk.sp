#include <sourcemod>
#include <morecolors>
#include <sdktools>

#define NMR_MAXPLAYERS 9

float  g_AfkUntilTime[NMR_MAXPLAYERS + 1];
bool   g_IsAfk[NMR_MAXPLAYERS + 1];
float  g_LastActivityTime[NMR_MAXPLAYERS + 1];

char   g_OriginalName[NMR_MAXPLAYERS + 1][MAX_NAME_LENGTH];

bool   g_IgnoreNameChange = false;

ConVar cvMaxAfkTime;
ConVar cvAutoAfkTime;
ConVar cvAutoKickTime;

Regex  g_TagRegex;

public Plugin myinfo =
{
	name		= "AFK Fucker",
	author		= "Dysphie",
	description = "Stops goobers from preventing map progress",
	version		= "",
	url			= ""
};

public void OnPluginStart()
{
	char error[32];
	g_TagRegex = new Regex("\\[AFK: .+?\\]", _, error, sizeof(error));

	if (error[0])
	{
		SetFailState("Regex error: %s", error);
	}

	cvMaxAfkTime  = CreateConVar("afk_max_seconds", "180",
								 "Maximum time players are allowed to go AFK for, in seconds");

	cvAutoAfkTime = CreateConVar("afk_move_seconds", "90", "Players are made AFK after this many seconds");
	cvAutoKickTime = CreateConVar("afk_kick_seconds", "300", "Players are kicked for AFK after this many seconds");

	LoadTranslations("afk.phrases");
	RegConsoleCmd("sm_afk", Cmd_Afk, "Go AFK");
	RegAdminCmd("sm_testname", Cmd_TestName, ADMFLAG_BAN);

	CreateTimer(1.0, AfkWatchdog, _, TIMER_REPEAT);

	HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i))
		{
			OnClientConnected(i);
		}
	}
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client))
	{
		return;
	}

	g_LastActivityTime[client] = GetEngineTime();
}

Action Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
	if (g_IgnoreNameChange)
	{
		g_IgnoreNameChange = false;
		return Plugin_Handled;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	char newName[MAX_NAME_LENGTH];
	event.GetString("newname", newName, sizeof(newName));

	if (StripFakeAfkTag(newName, sizeof(newName)))
	{
		g_IgnoreNameChange = true;
		SetClientName(client, newName);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

bool StripFakeAfkTag(char[] name, int maxlen)
{
	int numMatches = g_TagRegex.MatchAll(name);

	if (numMatches > 0)
	{
		char matchedStr[MAX_NAME_LENGTH];
		for (int i = 0; i < numMatches; i++)
		{
			g_TagRegex.GetSubString(0, matchedStr, sizeof(matchedStr));
			ReplaceString(name, maxlen, matchedStr, "");
		}

		return true;
	}

	return false;
}

void SlayAfk(int client)
{
	ForcePlayerSuicide(client);
	CPrintToChat(client, "%t", "You Were Slain");
}

Action AfkWatchdog(Handle timer, any data)
{
	float curTime		 = GetEngineTime();
	float longestAfkTime = 0.0;

	int	  numActive		 = 0;
	int	  numAfks		 = 0;
	int	  numExpiredAfks = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		if (!IsPlayerAlive(i))
		{
			if (IsAfk(i)) {
				ExitAfk(i);
			}

			continue;
		}

		CheckShouldEnterAfk(i);

		if (!IsAfk(i))
		{
			numActive++;
			continue;
		}

		numAfks++;

		// Check if we are an expired AFK (AFK for longer than we promised)
		if (curTime > g_AfkUntilTime[i])
		{
			numExpiredAfks++;
		}

		BroadcastAfk(i);

		// Check if this is our newest AFK
		if (g_AfkUntilTime[i] > longestAfkTime)
		{
			longestAfkTime = g_AfkUntilTime[i];
		}
	}

	// PrintToServer("numActive %d, numAfks = %d, numExpiredAfks = %d", numActive, numAfks, numExpiredAfks);

	if (numActive > 0 || numAfks <= 0)
	{
		return Plugin_Continue;
	}

	if (numExpiredAfks < numAfks)
	{
		int	 timeLeft = RoundToNearest(longestAfkTime - curTime);
		char humanTime[32];
		SecondsToHumanTime(timeLeft, humanTime, sizeof(humanTime));
		PrintCenterTextAll("%t", "Nuke Inbound", humanTime);
	}
	else
	{
		SlayAllAfks();
	}

	return Plugin_Continue;
}

void SlayAllAfks()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsAfk(i) || !IsClientInGame(i))
		{
			continue;
		}

		SlayAfk(i);
		ExitAfk(i);
	}
}
void CheckShouldEnterAfk(int client)
{
	if (g_IsAfk[client])
	{
		return;
	}

	float idleTime = GetIdleTime(client);
	if (idleTime >= cvAutoAfkTime.FloatValue)
	{
		EnterAfk(client);
	}

	if (idleTime >= cvAutoKickTime.FloatValue)
	{
		KickClient(client, "%t", "You Were Kicked");
	}
}

void ExitAfk(int client, bool byChoice = false)
{
	g_IsAfk[client]		   = false;
	g_AfkUntilTime[client] = 0.0;
	g_IgnoreNameChange	   = true;
	SetClientName(client, g_OriginalName[client]);

	if (byChoice)
	{
		CPrintToChatAll("%t", "Player Exited Afk", client);
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("IsAFK", Native_IsAFK);
	return APLRes_Success;
}

bool IsValidClient(int client)
{
	return 0 < client <= MaxClients && IsClientInGame(client);
}

int Native_IsAFK(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClient(client))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid client or client not in-game (%d)", client);
	}

	return g_IsAfk[client];
}

public void OnClientConnected(int client)
{
	g_IsAfk[client]			   = false;
	g_AfkUntilTime[client]	   = 0.0;
	g_LastActivityTime[client] = GetEngineTime();
	g_OriginalName[client]	   = "";

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	
	if (StripFakeAfkTag(name, sizeof(name))) {
		SetClientName(client, name);
	}
}

Action Cmd_Afk(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "In-game command only");
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(client))
	{
		CReplyToCommand(client, "%t", "Must Be Alive");
		return Plugin_Handled;
	}

	if (g_IsAfk[client])
	{
		CReplyToCommand(client, "%t", "Already AFK");
		return Plugin_Handled;
	}

	float minutes = GetCmdArgFloat(1);
	int	  seconds = clamp(RoundToNearest(minutes * 60.0), 30, cvMaxAfkTime.IntValue);
	EnterAfk(client, seconds);
	return Plugin_Handled;
}

void EnterAfk(int client, int seconds = 0)
{
	g_AfkUntilTime[client] = GetEngineTime() + float(seconds);
	g_IsAfk[client]		   = true;

	char humanSeconds[32];
	SecondsToHumanTime(seconds, humanSeconds, sizeof(humanSeconds));
	CPrintToChatAll("%t", (seconds == 0) ? "Player Was Made AFK" : "Player Went AFK", client, humanSeconds);

	GetClientName(client, g_OriginalName[client], sizeof(g_OriginalName[]));
}

// Returns the value clamped between min and max
any clamp(any value, any min, any max)
{
	if (value < min)
	{
		return min;
	}
	if (value > max)
	{
		return max;
	}

	return value;
}

Action Cmd_TestName(int client, int args)
{
	char playerName[PLATFORM_MAX_PATH];
	GetCmdArg(1, playerName, sizeof(playerName));

	int numMatches = g_TagRegex.MatchAll(playerName);
	if (numMatches > 0)
	{
		char matchedStr[MAX_NAME_LENGTH];
		for (int i = 0; i < numMatches; i++)
		{
			g_TagRegex.GetSubString(0, matchedStr, sizeof(matchedStr));
			ReplaceString(playerName, sizeof(playerName), matchedStr, "*");
		}
	}

	CReplyToCommand(client, "Fixed name: \"%s\"", playerName);
	return Plugin_Handled;
}

void SecondsToHumanTime(int secs, char[] buffer, int maxlen)
{
	int minutes		  = secs / 60;
	int remainingSecs = secs % 60;
	Format(buffer, maxlen, "%02d:%02d", minutes, remainingSecs);
}

void BroadcastAfk(int client)
{
	char buffer[MAX_NAME_LENGTH];
	int	 timeLeft = RoundToNearest(g_AfkUntilTime[client] - GetEngineTime());
	if (timeLeft < 0.0)
	{
		Format(buffer, sizeof(buffer), "[AFK] %s", g_OriginalName[client]);
	}
	else
	{
		SecondsToHumanTime(timeLeft, buffer, sizeof(buffer));

		Format(buffer, sizeof(buffer), "[AFK: %s] %s", buffer, g_OriginalName[client]);
	}

	g_IgnoreNameChange = true;
	SetClientName(client, buffer);
}

int g_oldButtons[NMR_MAXPLAYERS + 1];

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (buttons == g_oldButtons[client])
	{
		return;
	}

	g_oldButtons[client] = buttons;
	if (g_IsAfk[client])
	{
		ExitAfk(client, true);
	}

	g_LastActivityTime[client] = GetEngineTime();
}

float GetIdleTime(int client)
{
	// Dead players are never AFK
	if (!IsPlayerAlive(client) || !g_LastActivityTime[client])
	{
		return 0.0;
	}

	return GetEngineTime() - g_LastActivityTime[client];
}

bool IsAfk(int client)
{
	return g_IsAfk[client];
}
