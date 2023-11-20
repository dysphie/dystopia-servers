

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
	name = "/kill",
	author = "Dysphie",
	description = "Description",
	version = "Version",
	url = "URL"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_kill", Cmd_kill, "Commit suicide");
}

Action Cmd_kill(int client, int args)
{
	ForcePlayerSuicide(client);
	return Plugin_Handled;
}