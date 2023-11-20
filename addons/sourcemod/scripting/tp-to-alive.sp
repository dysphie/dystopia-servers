#include <sourcemod>
#include <sdktools>

public void OnPluginStart()
{
	RegAdminCmd("sm_alive", Cmd_Alive, ADMFLAG_CHEATS);
	RegAdminCmd("sm_tptoalive", Cmd_TpToAlive, ADMFLAG_CHEATS);
}

Action Cmd_TpToAlive(int client, int args)
{
	char cmdTarget[66];
	GetCmdArg(1, cmdTarget, sizeof(cmdTarget));

	int target = FindTarget(client, cmdTarget);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			float otherPos[3];
			GetClientAbsOrigin(i, otherPos);
			TeleportEntity(target, otherPos);
			PrintToChatAll("Teleported %N to %N", target, i);
			break;
		}
	}
	return Plugin_Handled;
}

Action Cmd_Alive(int client, int args)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			PrintToServer("%N (userid %d) is alive", i, GetClientUserId(i));
		}
	}
	return Plugin_Handled;
}