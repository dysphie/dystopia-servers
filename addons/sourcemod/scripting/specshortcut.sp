#include <sourcemod>
#include <morecolors>

public Plugin myinfo =
{
	name = "Spec Shortcuts",
	author = "Dysphie",
	description = "Implements !spec shortcuts",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	LoadTranslations("specshortcuts.phrases");
	RegConsoleCmd("sm_spec", Cmd_Spec);
}

Action Cmd_Spec(int client, int args)
{
	if (!client) {
		return Plugin_Handled;
	}

	if (args < 1) 
	{
		CReplyToCommand(client, "%t", "Usage");
		return Plugin_Handled;
	}

	if (IsPlayerAlive(client))
	{
		CReplyToCommand(client, "%t", "Must be dead");
		return Plugin_Handled;
	}

	char targetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, targetName, sizeof(targetName));

	int target = GetPlayerByName(targetName);
	if (target != -1) 
	{
		FakeClientCommand(client, "spec_mode 4"); // OBS_MODE_IN_EYE
		FakeClientCommand(client, "spec_player %d", target);
	}

	return Plugin_Handled;
}

int GetPlayerByName(const char[] partialName)
{
	char playerName[MAX_NAME_LENGTH];
	for (int i = 1; i <= MaxClients; i++) 
	{
		if (IsClientInGame(i) && IsPlayerAlive(i)) 
		{
			GetClientName(i, playerName, sizeof(playerName));
			if (StrContains(playerName, partialName, false)) 
			{
				return i;
			}
		}
	}
	return -1;
}