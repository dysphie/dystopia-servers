#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <morecolors>

bool g_IsLuxUmbra;

int g_NumMentosDestroyed;

ConVar cvGravity;

public Plugin myinfo =
{
    name = "Lux Umbra Manager",
    author = "Dysphie",
    description = "",
    version = "",
    url = ""
};

public void OnPluginStart()
{
    LoadTranslations("luxumbra.phrases");
}

public void OnMapStart()
{
    cvGravity = FindConVar("sv_gravity");

    char mapName[MAX_NAME_LENGTH];
    GetCurrentMap(mapName, sizeof(mapName));

    g_IsLuxUmbra = StrContains(mapName, "nmo_lux_umbra") != -1;

    if (g_IsLuxUmbra)
    { 
        HookEntityOutput("func_button", "OnPressed", OnButtonPressed);
        HookEntityOutput("func_breakable", "OnBreak", OnBreakableBroken);
    }

    HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);
}

public void OnMapEnd()
{
    if (g_IsLuxUmbra) 
    {
        UnhookEntityOutput("func_button", "OnPressed", OnButtonPressed);
        UnhookEntityOutput("func_breakable", "OnBreak", OnBreakableBroken);
    }
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_IsLuxUmbra) {
        return;
    }

    g_NumMentosDestroyed = 0;
    cvGravity.FloatValue = 800.0;
}

void OnButtonPressed(const char[] output, int button, int activator, float delay)
{
    if (!IsPlayerActivator(activator)) {
        return;
    }

    char targetname[32];
    GetEntityTargetname(button, targetname, sizeof(targetname));
    
    if (StrEqual(targetname, "counter_button0")) 
    {
        OnMentosEatid(activator);
    }
    else if (StrEqual(targetname, "st1_break5_r"))
    {  
        CPrintToChatAll("%t", "Destroyed Left Side Core", activator);
    }
    else if (StrEqual(targetname, "st1_break5_l"))
    {
        CPrintToChatAll("%t", "Destroyed Right Side Core", activator);
    }
    else if (StrEqual(targetname, "st1_button1"))
    {
        CPrintToChatAll("%t", "Destroyed Central Core", activator);
    }
}

Action OnBreakableBroken(const char[] output, int breakable, int activator, float delay)
{
    char model[PLATFORM_MAX_PATH];
    GetEntPropString(breakable, Prop_Data, "m_ModelName", model, sizeof(model));
    if (StrEqual(model, "*224"))
    {
        OnMentosEatid(activator); 
    }

    return Plugin_Continue;  
}

void OnMentosEatid(int causer)
{
    g_NumMentosDestroyed++

    if (IsPlayerActivator(causer)) {
        CPrintToChatAll("%t", "Player Destroyed 23-Core", causer, g_NumMentosDestroyed);
    } else {
        CPrintToChatAll("%t", "Something Destroyed 23-Core", g_NumMentosDestroyed);
    }
}

int GetEntityTargetname(int entity, char[] buffer, int maxlen)
{
    return GetEntPropString(entity, Prop_Send, "m_iName", buffer, maxlen);
}

bool IsPlayerActivator(int client)
{
    return 0 < client <= MaxClients;
}