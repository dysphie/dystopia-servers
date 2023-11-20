

#include <sdktools>
#include <sdkhooks>
#include <morecolors>
#include <gamestyles>
#include <sqlitebans>

#define NMR_MAXPLAYERS 9

#define FORBID_RADIUS 40.0
#define FORBID_DIAMETER 80.0

public Plugin myinfo =
{
	name = "Gameplay Styles",
	author = "Dysphie",
	description = "",
	version = "",
	url = ""
};

#define IN_SHOVE (1 << 27)

bool redrawingMenu;
Handle redrawMenuTimer[NMR_MAXPLAYERS+1];
int g_ActiveStyles[NMR_MAXPLAYERS + 1];
float roundStartTime = -1.0;

ConVar cvLowStamLimit;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("GetClientStyles", Native_GetClientStyles);
	//CreateNative("GetStylePhrase", Native_GetStylePhrase);
	return APLRes_Success;
}

any Native_GetStylePhrase(Handle plugin, int numParams)
{
	int style = GetNativeCell(1);

	for (int i = 0; i < MAX_STYLES; i++)
	{
		if ((1 << i) == style)
		{
			SetNativeString(2, styleNames[i], GetNativeCell(3));
			return true;
		}
	}

	return false;
}

any Native_GetClientStyles(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return g_ActiveStyles[client];
}

public void OnPluginStart()
{
	HookEvent("zombie_shoved", OnZombieShoved);

	cvLowStamLimit = CreateConVar("style_low_stamina_amount", "40");
	LoadTranslations("gamestyles.phrases");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}

	HookEvent("state_change", Event_StateChanged);
	HookEvent("player_death",  Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_extracted", Event_PlayerExtracted);
	RegConsoleCmd("sm_styles", Cmd_Styles);
	RegConsoleCmd("sm_style", Cmd_Styles);
	RegConsoleCmd("sm_mode", Cmd_Styles);
	RegConsoleCmd("sm_modes", Cmd_Styles);
	RegConsoleCmd("sm_modo", Cmd_Styles);
	RegConsoleCmd("sm_modos", Cmd_Styles);
	//RegConsoleCmd("debug_ActiveStyles", Cmd_DebugStyle);
}

void OnZombieShoved(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("player_id");
	RemoveStyle(client, STYLE_NOSHOVE);
}

void Event_PlayerExtracted(Event event, const char[] name, bool dontBroadcast)
{
	// if (!IsRoundOnGoing()) {
	// 	return;
	// }

	// int client = event.GetInt("player_id");
	// //PrintStyles(client);
}

float g_FirstSpawnPos[NMR_MAXPLAYERS+1][3];
bool g_InSetupCircle[NMR_MAXPLAYERS+1];

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !NMRiH_IsPlayerAlive(client)) {
		return;
	}

	if (IsRoundOnGoing() && !GetClientDeaths(client) && GetRoundElapsedTime() < 300.0)
	{
		// First time spawning
		BeginStyleTime(client);	
	}
}

void BeginStyleTime(int client)
{
	GetClientAbsOrigin(client, g_FirstSpawnPos[client]);
	g_InSetupCircle[client] = true;

	CreateTimer(0.1, CircleThink, GetClientSerial(client), TIMER_REPEAT);

	AddStyle(client, STYLE_NOSHOVE);
	AddStyle(client, STYLE_NODMG);
	AddStyle(client, STYLE_RANKED);
}

Action CircleThink(Handle timer, int clientSerial)
{
	int client = GetClientFromSerial(clientSerial);
	if (!client || !IsClientInGame(client) || !IsPlayerAlive(client) || !IsRoundOnGoing()) 
	{
		g_InSetupCircle[client] = false;
		return Plugin_Stop;
	}

	float clientPos[3];
	GetClientAbsOrigin(client, clientPos);

	if (GetVectorDistance(clientPos, g_FirstSpawnPos[client]) > FORBID_RADIUS) 
	{
		g_InSetupCircle[client] = false;
		OnClientLeaveStyleCircle(client);
		return Plugin_Stop;
	}
	
	//DrawStyleCircle(client);
	return Plugin_Continue;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && IsClientInGame(client)) {
		OnClientDied(client)
	}
}

float GetRoundElapsedTime()
{
	return GetGameTime() - roundStartTime;
}

Action Cmd_Styles(int client, int args)
{
	if (!client) {
		client = 1;
	}

	ShowStylesMenu(client);
	redrawMenuTimer[client] = CreateTimer(0.1, Timer_RedrawStyleMenu, GetClientSerial(client), TIMER_REPEAT);
	return Plugin_Handled;
}

bool IsManualStyle(int style)
{
	return style == STYLE_BAN || style == STYLE_LOWSTAM;
}

#include <debugoverlays>

int MenuHandler_Style(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End) 
	{
		delete menu;
	}
	else if (action == MenuAction_Cancel)
	{
		if (!redrawingMenu) 
		{
			delete redrawMenuTimer[param1]; 
		}
	}
	else if (action == MenuAction_Select)
	{	
		int client = param1;

		if (g_InSetupCircle[client]) 
		{
			char selection[12];
			menu.GetItem(param2, selection, sizeof(selection));

			int style = StringToInt(selection);

			if (HasStyle(client, style)) 
			{
				RemoveStyle(client, style); // TODO : TryRemoveStyle
				ShowStylesMenu(param1);
			} 
			else
			{
				if (style == STYLE_BAN)
				{
					delete redrawMenuTimer[param1]; 
					ConfirmBanStyleMenu(client);
				}
				else
				{
					TryAddStyle(client, style);
					ShowStylesMenu(client);
				}
			}
		}
	}

	return 0;
}

void ConfirmBanStyleMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ConfirmBanStyle);
	menu.SetTitle("%T", "Are You Sure Ban Style", client);

	char buffer[32];
	FormatEx(buffer, sizeof(buffer), "%T", "Confirm Ban Style Yes", client);
	menu.AddItem("y", buffer);
	FormatEx(buffer, sizeof(buffer), "%T", "Confirm Ban Style No", client);
	menu.AddItem("n", buffer);

	menu.Display(client, 10);
}

int MenuHandler_ConfirmBanStyle(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action == MenuAction_Select)
	{
		int client = param1;

		char selection[2];
		menu.GetItem(param2, selection, sizeof(selection));

		if (selection[0] == 'y')
		{
			TryAddStyle(client, STYLE_BAN);
		}

		ShowStylesMenu(client);
		redrawMenuTimer[client] = CreateTimer(0.1, Timer_RedrawStyleMenu, GetClientSerial(client), TIMER_REPEAT);
	}

	return 0;
}

void TryAddStyle(int client, int style)
{
	if (!g_InSetupCircle[client]) 
	{
		CPrintToChat(client, "%t", "Can't Toggle Outside of Circle");
		return;
	}

	if (HasStyle(client, style))
	{
		CPrintToChat(client, "%t", "Already Have Style");
		return;
	}

	AddStyle(client, style);
}

void OnClientLeaveStyleCircle(int client)
{
	for (int i = 1; i < MAX_STYLES; i++)
	{
		int style = (1 << i);
		if (HasStyle(client, style) && IsManualStyle(style))
		{
			char phrase[32];
			GetStylePhrase(style, phrase, sizeof(phrase));
			CPrintToChatAll("%t", "Client Enabled Manual Style", client, phrase);
		}
	}
}

void ShowStylesMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Style);

	char info[12];
	char buffer[255];


	menu.SetTitle("%T\n \n%T\n \n", "Style Menu Title", client, "Explain Circle", client);
	
	for (int i = 1; i < MAX_STYLES; i++)
	{
		int style = (1 << i);
		bool enabled = HasStyle(client, style);

		int itemDraw = ITEMDRAW_DEFAULT;
		if (!g_InSetupCircle[client] || !IsManualStyle(style)) {
			itemDraw = ITEMDRAW_DISABLED;
		}

		Format(buffer, sizeof(buffer), "%s %T",
			enabled ? " [ ✓ ]" : " [      ]", 
			styleNames[i], client);

		CRemoveTags(buffer, sizeof(buffer)); // HACKHACK: We rly need a better solution to this

		IntToString(style, info, sizeof(info));
		menu.AddItem(info, buffer, itemDraw);
	}

	menu.Display(client, 5);
}

Action Timer_RedrawStyleMenu(Handle timer, int clientSerial)
{
	int client = GetClientFromSerial(clientSerial);
	if (client && IsClientInGame(client)) 
	{
		redrawingMenu = true;
		ShowStylesMenu(client);
		redrawingMenu = false;
	} 

	return Plugin_Continue;
}

// Action Cmd_DebugStyle(int client, int args)
// {
// 	PrintStyles(client);
// 	return Plugin_Handled;
// }

void PrintStyles(int client)
{
	if (!client) {
		client = 1;
	}

	// char buffer[1024];

	// for (int i = 0; i < 5; i++)
	// {
	// 	if (g_ActiveStyles[client] & (1 << i))
	// 	{
	// 		Format(buffer, sizeof(buffer), "%s%s ", buffer, styleNames[i]);
	// 	}
	// }
	// PrintToChat(client, "Styles: %s", buffer);
	for (int i = 1; i < MAX_STYLES; i++)
	{
		int style = (1 << i);
		CPrintToChat(client, "%s%s", styleNames[i], HasStyle(client, style) ? " {green}✔" : " {red}✘");
	}

	
}

#define STATE_ROUND_START 3
#define STATE_ROUND_OVERRUN 6
#define GAMEMODE_NMO	  0

void Event_StateChanged(Event event, const char[] name, bool dontBroadcast)
{
	int gameMode = event.GetInt("game_type");
	int state	 = event.GetInt("state");

	if (gameMode == GAMEMODE_NMO)
	{
		// Server event "state_change", Tick 20258: // Overrun state
		// - "state" = "6"
		// - "game_type" = "0"
		bool roundRestarted = (state == STATE_ROUND_START);
		bool roundFailed = (state == STATE_ROUND_OVERRUN);
		
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client))
			{
				if (roundFailed && HasStyle(client, STYLE_BAN)) {
					FailBanStyle(client);
				}

				ClearStyles(client);
			}
		}

		if (roundRestarted) {
			OnRoundStart();
		}
	}
}

void FailBanStyle(int client)
{
	float elapsed = GetRoundElapsedTime();

	if (elapsed < 60.0) {
		elapsed = 60.0; // Shortest ban duration is 1 min
	}
	
	int elapsedMins = RoundToFloor(elapsed / 60.0);
	if (elapsedMins < 1) {
		elapsedMins = 1;
	}
	//PrintToServer("Banned %N for %d mins cuz banmode", client, elapsedMins);

	char humanBanTime[32];
	SecondsToHumanTime(elapsed, humanBanTime, sizeof(humanBanTime), false);

	char kickMsg[255];
	Format(kickMsg, sizeof(kickMsg), "%T", "Failed Ban Mode Kick Message", client, humanBanTime);

	RemoveStyle(client, STYLE_BAN);

	char steamid[32];
	if (GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid))) 
	{
		CPrintToChatAll("%t", "Failed Ban Mode", client, "STYLE_BAN", humanBanTime);
		SqliteBan(steamid, elapsedMins, kickMsg, "game");
	}
}

void OnRoundStart()
{
	roundStartTime = GetGameTime();

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsPlayerAlive(client))
		{
			BeginStyleTime(client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnClientDamaged);
		SDKHook(client, SDKHook_PreThink, OnClientPreThink);
	}
}

void OnClientPreThink(int client)
{
	if (HasStyle(client, STYLE_LOWSTAM))
	{
		float stamina = GetEntPropFloat(client, Prop_Send, "m_flStamina");
		float maxStamina = cvLowStamLimit.FloatValue;
		if (stamina > maxStamina) {
			SetEntPropFloat(client, Prop_Send, "m_flStamina", maxStamina);
		}
	}
}

void OnClientDamaged(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3])
{
	RemoveStyle(victim, STYLE_NODMG);
}

public void OnClientDisconnect(int client)
{
	redrawMenuTimer[client] = null;
	g_InSetupCircle[client] = false;
	ClearStyles(client);
}

public void OnClientDied(int client)
{
	g_InSetupCircle[client] = false;

	if (HasStyle(client, STYLE_BAN)) 
	{
		FailBanStyle(client);
		return;
	}

	RemoveStyle(client, STYLE_RANKED);
	RemoveStyle(client, STYLE_NODMG); // Client can die without taking damage
}


int IsRoundOnGoing()
{
	return roundStartTime != -1.0 && GameRules_GetProp("_roundState") == STATE_ROUND_START;
}

void AddStyle(int client, int style)
{
	if (g_ActiveStyles[client] & style == style) {
		return;
	}
	
	g_ActiveStyles[client] |= style;
	OnStyleAdded(client, style);
}

void OnStyleAdded(int client, int style)
{
}

void OnStyleRemoved(int client, int style)
{
}

void RemoveStyle(int client, int style)
{
	if (g_ActiveStyles[client] & style) 
	{
		g_ActiveStyles[client] &= ~style;
		OnStyleRemoved(client, style);
	}
}

int IsEntityPlayer(int entity)
{
	return 0 < entity <= MaxClients;
}

void ClearStyles(int client)
{
	g_ActiveStyles[client] = 0;
}

bool HasStyle(int client, int style)
{
	return g_ActiveStyles[client] & style == style;
}


bool CouldDisableStyle(int client, int style)
{
	return g_InSetupCircle[client] && IsManualStyle(style);
}

int g_LaserIndex;
int g_HaloIndex;

public void OnMapStart()
{
	g_LaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_HaloIndex = PrecacheModel("materials/sprites/halo01.vmt");
}

void DrawStyleCircle(int client)
{
	if (!g_InSetupCircle[client]) {
		return;
	}
	
	TE_SetupBeamRingPoint(g_FirstSpawnPos[client], FORBID_DIAMETER, FORBID_DIAMETER+0.1, g_LaserIndex, g_HaloIndex, 
		0, 15, 0.2, 0.2, 0.0, {255, 0, 0, 255}, 10, 0);
	TE_SendToClient(client); 
}

void SecondsToHumanTime(float value, char[] buffer, int maxlen, bool includeMilli = true)
{
	bool neg = value < 0.0;
	if (neg) {
		value = -value;
	}

	int secs    = RoundToFloor(value);
	int milli   = RoundToFloor((value - float(secs)) * 1000);
	int minutes = secs / 60;
	int seconds = secs % 60;

	if (includeMilli) {
		Format(buffer, maxlen, "%s%02d:%02d.%03d",  neg ? "-" : "", minutes, seconds, milli);
	} else {
		Format(buffer, maxlen, "%s%02d:%02d",  neg ? "-" : "", minutes, seconds);
	}
}

#define STATE_ACTIVE 0
bool NMRiH_IsPlayerAlive(int client)
{
	return IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_iPlayerState") == STATE_ACTIVE;
}