#include <sourcemod>
#include <sdktools>

ConVar cvDiff;
bool isFallout;

public Plugin myinfo = {
    name        = "Fallout Limbo Manager",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

public void OnPluginStart()
{
	cvDiff = CreateConVar("sm_fallout_limbo_difficulty", "easy");
	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));
	isFallout = StrContains(mapName, "nmo_falloutlimbo") == 0;

	if (isFallout)
	{
		int button = FindEntityByTargetame("func_button", "bu1");	
		if (button != -1) {
			RemoveEntity(button);
		} 
		
		button = FindEntityByTargetame("func_button", "bu2");	
		if (button != -1) {
			RemoveEntity(button);
		}

		button = FindEntityByTargetame("func_button", "bu3");	
		if (button != -1) {
			RemoveEntity(button);
		}
	}
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	if (!isFallout) {
		return;
	}

	char diff[32];
	cvDiff.GetString(diff, sizeof(diff));

	int button = -1;
	char buttonName[30];

	if (StrEqual(diff, "easy", false)) {
		buttonName = "bu1";
	} else if (StrEqual(diff, "normal", false)) {
		buttonName = "bu2";	
	} else if (StrEqual(diff, "hard", false)) {
		buttonName = "bu3";
	} else {
		return;
	}

	PrintToServer("Round restarted, pressing button %s", buttonName);

	button = FindEntityByTargetame("func_button", buttonName);	
	if (button != -1) {
		AcceptEntityInput(button, "Press", button, button);
	}
}



int FindEntityByTargetame(const char[] classname, const char[] targetname)
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