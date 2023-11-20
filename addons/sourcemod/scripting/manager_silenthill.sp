#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo = {
    name        = "Silent Hill Manager",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

bool g_Enabled = false;
ConVar cvStage;

public void OnPluginStart()
{
	cvStage = CreateConVar("sm_silent_hill_stage", "1");
	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_Pre);
	RegAdminCmd("admin_silent", Cmd_AdminSilent, ADMFLAG_ROOT);
}

Action Cmd_AdminSilent(int client, int args)
{
	TeleportEntity(client, {-15071.0, 13073.0, -596.0});
	return Plugin_Handled;
}

Action OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	SetStageByConVar();
	return Plugin_Continue;
}

void SetStageByConVar()
{
	if (!g_Enabled) {
		return;
	}

	int logicCase = FindEntityByName(-1, "logic_case", "case");
	if (!logicCase) 
	{
		LogError("Couldn't patch map, no 'case' entity");
		return ;
	}

	SetVariantInt(cvStage.IntValue);
	AcceptEntityInput(logicCase, "InValue");

	char variantStr[32];
	Format(variantStr, sizeof(variantStr), "OnUser1 math:SetValue:%d:0:1", cvStage.IntValue);
	SetVariantString(variantStr);
	AcceptEntityInput(0, "AddOutput");
	AcceptEntityInput(0, "FireUser1");

	PrintToServer("Set stage to %d", cvStage.IntValue);
}

public void OnConfigsExecuted()
{
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));
	g_Enabled = StrContains(mapName, "nmo_silent_hill_blackblood") != -1;

	SetStageByConVar();
}

int FindEntityByName(int e, const char[] classname, const char[] targetname)
{
	while ((e = FindEntityByClassname(e, classname)) != -1)
	{
		char buffer[32];
		GetEntPropString(e, Prop_Data, "m_iName", buffer, sizeof(buffer));

		if (StrEqual(buffer, targetname))
		{
			return e;
		}
	}

	return -1;
}