#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

ConVar cvEnable;
Handle g_HudSync;

public Plugin myinfo =
{
    name = "Breakable Progress",
    author = "Dysphie",
    description = "",
    version = "",
    url = ""
};

bool g_Lateloaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_Lateloaded = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_HudSync = CreateHudSynchronizer();
    cvEnable = CreateConVar("sm_show_breakable_progress", "1");
}

public void OnMapStart()
{
    if (!g_Lateloaded) {
        return;
    }

    int e = -1;
    while ((e = FindEntityByClassname(e, "func_breakable")) != -1) {
        OnBreakableCreated(e);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "func_breakable")) {
        OnBreakableCreated(entity);
    }
}

void OnBreakableCreated(int breakable)
{
     SDKHook(breakable, SDKHook_OnTakeDamagePost, OnBreakableDamage);
}

void OnBreakableDamage(int breakable, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom)
{
    if (!IsPlayer(attacker) || !cvEnable.BoolValue) {
        return;
    }   

    int health = GetEntProp(breakable, Prop_Data, "m_iHealth");

    SetHudTextParams(0.45, 0.85, 3.0, 0, 255, 0, 255, _, 0.0, 0.0, 0.0);
    ShowSyncHudText(attacker, g_HudSync, "HP: %d", health);
}

bool IsPlayer(int client)
{
    return 0 < client <= MaxClients;
}