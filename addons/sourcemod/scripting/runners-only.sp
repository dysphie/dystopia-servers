#include <sdktools>
#include <sdkhooks>

public Plugin myinfo = 
{
    name        = "Shamblers To Runners",
    author      = "Dysphie",
    description = "Turns shamblers into runners",
    version     = "1.0.0",
    url         = ""
};

ConVar g_cvEnabled;
bool g_bEnabled;

public void OnPluginStart()
{
	g_cvEnabled = CreateConVar("runners_only", "1");
	g_cvEnabled.AddChangeHook(OnCvarChanged);
	CacheConVarValue();
}

void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	CacheConVarValue();
}

void CacheConVarValue()
{
	g_bEnabled = g_cvEnabled.BoolValue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (g_bEnabled && StrEqual(classname, "npc_nmrih_shamblerzombie"))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnShamblerSpawned);
	}
}

void OnShamblerSpawned(int shambler)
{
	SetVariantString("!activator");
	AcceptEntityInput(shambler, "BecomeRunner", shambler, shambler);
}