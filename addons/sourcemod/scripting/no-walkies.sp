#include <sourcemod>
#include <sdkhooks>

public Plugin myinfo = {
    name        = "No Walkietalkies",
    author      = "Dysphie",
    description = "Removes walkietalkies from the game",
    version     = "1.0.0",
    url         = ""
};

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "item_walkietalkie"))
	{
		SDKHook(entity, SDKHook_Spawn, OnWalkieSpawn);
	}
}

Action OnWalkieSpawn(int walkie)
{
	return Plugin_Handled;
}