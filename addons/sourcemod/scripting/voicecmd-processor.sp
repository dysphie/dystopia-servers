#include <sourcemod>
#include <sdktools>
#include <namecolors>
#include <morecolors>

public Plugin myinfo = {
    name        = "Radial Command Processor",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

enum 
{
	VOICECMD_AMMO = 0,
	VOICECMD_FOLLOW,
	VOICECMD_HELP,
	VOICECMD_NO,
	VOICECMD_STAY,
	VOICECMD_THANKS,
	VOICECMD_YES,
	VOICECMD_INCOMING,
	VOICECMD_INJURED,
	VOICECMD_FIREINTHEHOLE,
	VOICECMD_TAUNT,
	VOICECMD_PAIN,
	VOICECMD_DEATH,
	VOICECMD_BLEEDOUT,
	VOICECMD_DROWN,
	NUM_VOICE_COMMANDS
}

#define AMMO_GRENADE 9
#define AMMO_MOLOTOV 10
#define AMMO_TNT 11

char voiceToken[][] = {

	"NMRiH_VoiceCommand_Ammo",
	"NMRiH_VoiceCommand_Follow",
	"NMRiH_VoiceCommand_Help",
	"NMRiH_VoiceCommand_No",
	"NMRiH_VoiceCommand_Stay",
	"NMRiH_VoiceCommand_ThankYou",
	"NMRiH_VoiceCommand_Yes",
	"NMRiH_VoiceCommand_Incoming",
	"NMRiH_VoiceCommand_Injured",
	"",	   // Generic nade
	"NMRiH_VoiceCommand_Taunt"
}

ConVar cvAllTalk;
ConVar cvChatAtten;
ConVar cvMaxCmds;

#define NMR_MAXPLAYERS 9

int numCmds[NMR_MAXPLAYERS+1];
int g_WantsSubtitles[NMR_MAXPLAYERS+1] = { true, ... };

public void OnPluginStart()
{
	cvAllTalk	= FindConVar("sv_alltalk");
	cvChatAtten = FindConVar("chat_atten_max");
	cvMaxCmds = CreateConVar("sv_voicecmd_max_cmds", "100");

	LoadTranslations("voicecmd.phrases");
	AddTempEntHook("TEVoiceCommand", OnVoiceCommand);

	UserMsg msgID = GetUserMessageId("VoiceSubtitle");
	if (msgID == INVALID_MESSAGE_ID)
	{
		SetFailState("Unsupported game or game version");
	}

	HookUserMessage(msgID, OnVoiceSubtitle, true);

	RegAdminCmd("debug_voicecmds", Cmd_DebugCmds, ADMFLAG_GENERIC);
}

Action Cmd_DebugCmds(int client, int args)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			ReplyToCommand(client, "%d voicecmds for \"%N\"", numCmds[i], i);
		}
	}
	return Plugin_Handled;
}

void QueryResult_WantsSubtitle(QueryCookie cookie, int client, ConVarQueryResult result, 
	const char[] cvarName, const char[] cvarValue)
{
	if (result != ConVarQuery_Okay) {
		return;
	}

	g_WantsSubtitles[client] = StringToInt(cvarValue) != 0;
}

Action OnVoiceSubtitle(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	int author = msg.ReadByte();
	if (!IsValidClient(author))
	{
		return Plugin_Continue;
	}

	if (numCmds[author] > cvMaxCmds.IntValue) {
		return Plugin_Handled;
	}

	int cmd = msg.ReadByte();
	if (cmd >= view_as<int>(VOICECMD_PAIN))
	{
		return Plugin_Continue;
	}

	DataPack data = new DataPack();
	data.WriteCell(GetClientSerial(author));
	data.WriteCell(cmd);
	data.WriteCell(playersNum);
	data.WriteCellArray(players, playersNum);

	RequestFrame(Frame_CustomVoiceSubtitle, data);

	return Plugin_Handled;
}

void Frame_CustomVoiceSubtitle(DataPack data)
{
	data.Reset();
	int author = GetClientFromSerial(data.ReadCell());

	if (!author || !IsClientInGame(author)) {
		delete data;
		return;
	}

	int cmd = data.ReadCell();
	int playersNum = data.ReadCell();

	int[] players = new int[playersNum];

	data.ReadCellArray(players, playersNum);

	delete data;

	SendVoiceSubtitle(author, voiceToken[cmd], players, playersNum);
}

void SendVoiceSubtitle(int author, const char[] phrase, const int[] players, int playersNum)
{
	if (!phrase[0])
	{
		return;
	}

	char authorName[MAX_NAME_LENGTH];
	GetColoredName(author, authorName, sizeof(authorName));

	for (int i = 0; i < playersNum; i++)
	{
		int player = players[i];
		if (!g_WantsSubtitles[player] || !IsClientInGame(player)) {
			continue;
		}

		CPrintToChat(player, "(%t) %s: %t", "Voice", authorName, phrase);
	}
}

Action OnVoiceCommand(const char[] te_name, const int[] players, int numClients, float delay)
{
	int author = TE_ReadNum("_playerIndex");
	if (!IsValidClient(author))
	{
		return Plugin_Continue;
	}

	if (numCmds[author] > cvMaxCmds.IntValue) {
		return Plugin_Handled;
	}

	char authorName[MAX_NAME_LENGTH];
	GetColoredName(author, authorName, sizeof(authorName));

	int cmd = TE_ReadNum("_voiceCommand");
	if (cmd >= view_as<int>(VOICECMD_PAIN))
	{
		return Plugin_Continue;
	}
	
	numCmds[author]++;

	if (cmd == VOICECMD_TAUNT)
	{
		SendVoiceSubtitle(author, "NMRiH_VoiceCommand_Taunt", players, numClients);
		return Plugin_Continue;
	}

	if (cmd == VOICECMD_FIREINTHEHOLE)
	{
		int nadeType = ValidateNade(author);
		char buffer[32];

		switch (nadeType)
		{
			case AMMO_GRENADE:
			{
				buffer = "NMRiH_VoiceCommand_Grenade";
			}
			case AMMO_MOLOTOV:
			{
				buffer = "NMRiH_VoiceCommand_Molotov";
			}
			case AMMO_TNT:
			{
				buffer = "NMRiH_VoiceCommand_TNT";
			}
			default:
			{
				return Plugin_Handled;
			}
		}

		SendVoiceSubtitle(author, buffer, players, numClients);
	}

	return Plugin_Continue;
}


int ValidateNade(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon == -1) {
		return -1;
	}
	
	int ammoType  = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
	if (ammoType == -1) {
		return -1;
	}

	int ammoCount = GetEntProp(client, Prop_Send, "m_iAmmo", 4, ammoType);
	if (ammoCount != 0) {
		return -1;
	}

	return ammoType;
}

bool IsValidClient(int client)
{
	return 0 < client <= MaxClients && IsClientInGame(client);
}

bool PlayerCanHearChat(int listener, int speaker)
{
	if (!IsInGamePlayer(listener) || !IsInGamePlayer(speaker))
	{
		return false;
	}

	if (cvAllTalk.BoolValue)
	{
		return true;
	}

	if (IsClientObserver(speaker) || !IsPlayerAlive(speaker))
	{
		return IsClientObserver(listener) || !IsPlayerAlive(listener);
	}

	if (HasWalkieTalkie(speaker) && HasWalkieTalkie(listener))
	{
		return true;
	}

	float speakerPos[3]; float listenerPos[3];
	WorldSpaceCenter(speaker, speakerPos);
	WorldSpaceCenter(listener, listenerPos);

	return cvChatAtten.FloatValue >= GetVectorDistance(speakerPos, listenerPos);
}

public void OnClientConnected(int client)
{
	g_WantsSubtitles[client] = true;
	QueryClientConVar(client, "cl_voicesubtitles", QueryResult_WantsSubtitle);
	numCmds[client] = 0;
}

public void OnClientDisconnect(int client)
{
	numCmds[client] = 0;
}

bool IsInGamePlayer(int entity)
{
	return IsPlayer(entity) && IsClientInGame(entity);
}

bool IsPlayer(int entity)
{
	return 0 < entity <= MaxClients;
}

bool HasWalkieTalkie(int client)
{
	int max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < max; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon != -1)
		{
			char classname[18];
			GetEntityClassname(weapon, classname, sizeof(classname));

			if (StrEqual(classname, "item_walkietalkie"))
			{
				return true;
			}
		}
	}

	return false;
}

void WorldSpaceCenter(int client, float v[3])
{
	GetClientAbsOrigin(client, v);

	PrintToServer("Origin is %f %f %f", v[0], v[1], v[2]);
	float max[3];
	GetClientMaxs(client, max);

	// v[0] += max[0] / 2;
	// v[1] += max[1] / 2;
	v[2] += max[2] / 2;
	
	PrintToServer("Center is %f %f %f", v[0], v[1], v[2]);
}