#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

bool isSubside = false;
ConVar cvRequireBattery;

public void OnPluginStart()
{
	cvRequireBattery = CreateConVar("sm_subside_require_battery", "1");
	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
	char currentMap[MAX_NAME_LENGTH];
	GetCurrentMap(currentMap, sizeof(currentMap));
	isSubside = StrContains(currentMap, "nmo_subside") == 0;
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	if (!isSubside) {
		return;
	}

	if (cvRequireBattery.BoolValue)
	{
		GlowBatteryEntities();
	}

	int logic = FindEntityByTargetname("logic_branch", "bonus_branch");
	if (logic == -1) 
	{
		LogError("Couldn't find logic_branch");
		return;
	}

	HookSingleEntityOutput(logic, "OnFalse", OnLogicNoBattery);
}

void OnLogicNoBattery(const char[] output, int caller, int activator, float delay)
{
	if (!cvRequireBattery.BoolValue) {
		return;
	}

	int extZone = FindEntityByTargetname("func_nmrih_extractionzone", "ext");
	if (extZone != -1) 
	{
		SetVariantString("!activator");
		AcceptEntityInput(extZone, "Disable", extZone, extZone);
	}
}

int FindEntityByTargetname(const char[] classname, const char[] targetname)
{
	PrintToServer("Find by classname: %s and name %s", classname, targetname);
	int e = -1;
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

void GlowEntity(int entity, const char[] clr, bool blip)
{
    DispatchKeyValue(entity, "glowable", "1"); 
    DispatchKeyValueInt(entity, "glowblip", blip); 

    DispatchKeyValue(entity, "glowcolor", clr);
    DispatchKeyValue(entity, "glowdistance", "9999");

    SetVariantString("!activator");
    AcceptEntityInput(entity, "enableglow");
}

void GlowBatteryEntities()
{
	char targetName[30];
	for (int i = 1; i <= 8; i++)
	{
		Format(targetName, sizeof(targetName), "b%d_d", i);
		int lever = FindEntityByTargetname("prop_dynamic", targetName); 
		if (lever != -1) { 
			GlowEntity(lever, "255 255 255", false); 
			PrintToServer("GLOWING LEVER %s", targetName);
		} else {
			PrintToServer("Can't find lever %s", targetName);
		}
	}

	int batt = FindEntityByTargetname("prop_physics", "batt");
	if (batt != -1) {
		GlowEntity(batt, "255 0 0", true);
	}
}
