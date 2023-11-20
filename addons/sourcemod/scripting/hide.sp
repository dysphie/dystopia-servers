#include <morecolors>
#include <sdkhooks>

#define NMR_MAXPLAYERS 9


public Plugin myinfo = {
    name        = "Hide Players",
    author      = "Dysphie",
    description = "Adds command to show or hide other players",
    version     = "1.0.0",
    url         = ""
};


bool g_HideTeam[NMR_MAXPLAYERS];

public void OnPluginStart()
{
	LoadTranslations("hide.phrases");
	RegConsoleCmd("sm_esconder", Cmd_Hide, "Muestra u oculta a los otros jugadores");
	RegConsoleCmd("sm_ocultar", Cmd_Hide, "Muestra u oculta a los otros jugadores");
	RegConsoleCmd("sm_hide", Cmd_Hide, "Show or hide other players");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnClientTransmit);
}

Action OnClientTransmit(int client, int recipient)
{
	if (client == recipient) {
		return Plugin_Continue;
	}

	return  g_HideTeam[recipient] ? Plugin_Handled : Plugin_Continue; 
}

Action Cmd_Hide(int client, int args)
{
	g_HideTeam[client] = !g_HideTeam[client];
	CReplyToCommand(client, "%t", g_HideTeam[client] ? "Hid Team" : "Unhid Team");

	return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
	g_HideTeam[client] = false;
}