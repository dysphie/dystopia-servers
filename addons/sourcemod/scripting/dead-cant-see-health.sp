
#define STATE_ACTIVE 0

ConVar cvNeutralName;

public Plugin myinfo = {
    name        = "Neutral Name Spec",
    author      = "Dysphie",
    description = "",
    version     = "1.0.1",
    url         = ""
};

public void OnPluginStart()
{
	cvNeutralName = FindConVar("sv_neutral_player_name");

	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_extracted", OnPlayerExtracted);
	HookEvent("player_spawn", OnPlayerSpawn);
}

void OnPlayerExtracted(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("player_id");
	if (client && !NMRiH_IsPlayerAlive(client))
	{
		SendSeeHealth(client, "1");
	}
}

public void OnClientPostAdminCheck(int client)
{
	SendSeeHealth(client, "1");
}

void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && !NMRiH_IsPlayerAlive(client))
	{
		SendSeeHealth(client, "1");
	}
}

void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && NMRiH_IsPlayerAlive(client))
	{
		SendSeeHealth(client, "0");
	}
}

bool NMRiH_IsPlayerAlive(int client)
{
	return IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_iPlayerState") == STATE_ACTIVE;
}

void SendSeeHealth(int client, const char[] value)
{
	if (!IsFakeClient(client))
	{
		cvNeutralName.ReplicateToClient(client, value);
	}
}