#include <sourcemod>
#include <sdktools>

ConVar cvDifficulty;
bool isAbra;

public Plugin myinfo = {
    name        = "Abra Dungeon Manager",
    author      = "Dysphie",
    description = "",
    version     = "1.0.1",
    url         = ""
};

public void OnMapStart()
{
	cvDifficulty = CreateConVar("sm_abra_dungeon_difficulty", "hard", "nmo_abra_dungeon's difficulty, 'easy' or 'hard'");
	cvDifficulty.AddChangeHook(OnDifficultyChange);

	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));
	isAbra = StrContains(mapName, "nmo_abra_dungeon") != -1;
	
	TryPatchDumbAsFuck();
	//TryPatchMap();
}

void OnDifficultyChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
	TryPatchDumbAsFuck();
	//TryPatchMap();
}

public void OnPluginStart()
{
	HookEvent("nmrih_reset_map", OnMapReset, EventHookMode_PostNoCopy);
}

void OnMapReset(Event event, const char[] name, bool dontBroadcast)
{
	if (!isAbra) {
		return;
	}

	TryPatchDumbAsFuck();
	//TryPatchMap();
}

void TryPatchMap()
{
	char buffer[6];
	cvDifficulty.GetString(buffer, sizeof(buffer));

	int relay = -1;

	if (StrEqual(buffer, "easy", false)) 
	{
		relay = FindEntityByTargetame(-1, "logic_relay", "diff_easy_choise_logic");
	} 
	else if (StrEqual(buffer, "hard", false)) 
	{
		relay = FindEntityByTargetame(-1, "logic_relay", "diff_hard_choise_logic");
	}
	else
	{
		LogError("Got bogus value for sm_abra_dungeon_difficulty: \"%s\"", buffer);
		return;
	}

	if (relay == -1)
	{
		LogError("Could not locate difficulty relay");
		return;
	}
	else
	{
		SetVariantString("!activator");
		AcceptEntityInput(relay, "Trigger", relay, relay);
	}

	// Always remove boat buttons and walls
	RemoveByPrefix("func_brush", "diff_wall");
	RemoveByPrefix("trigger_progress_use", "spawn_1_");
	RemoveByPrefix("prop_dynamic", "diff_hard");
	RemoveByPrefix("prop_dynamic", "diff_easy");
}


// The smart way isn't working, let's go back to monki
void TryPatchDumbAsFuck()
{
	if (!isAbra) {
		return;
	}
	
	char buffer[10];
	cvDifficulty.GetString(buffer, sizeof(buffer));

	if (StrEqual(buffer, "hard", false)) 
	{
		PrintToServer("Choosing hard diff, cvar is %s", buffer);
		RemoveByPrefix("prop_dynamic", "diff_easy1");
		RemoveByPrefix("prop_dynamic", "diff_easy2");
		RemoveByPrefix("prop_dynamic", "diff_easy3");
		RemoveByPrefix("prop_dynamic", "diff_easy4");
		RemoveByPrefix("prop_dynamic", "diff_easy5");
		RemoveByPrefix("prop_dynamic", "diff_easy6");
		RemoveByPrefix("prop_dynamic", "diff_easy7");
		RemoveByPrefix("prop_dynamic", "diff_easy8");
		RemoveByPrefix("prop_dynamic", "diff_easy9");

		RemoveByPrefix("trigger_progress_use", "spawn_1_easy1_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy2_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy3_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy4_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy5_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy6_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy7_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy8_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_easy9_trigger");
	} 
	else if (StrEqual(buffer, "easy", false)) 
	{
		PrintToServer("Choosing easy diff, cvar is %s", buffer);
		RemoveByPrefix("prop_dynamic", "diff_hard1");
		RemoveByPrefix("prop_dynamic", "diff_hard2");
		RemoveByPrefix("prop_dynamic", "diff_hard3");
		RemoveByPrefix("prop_dynamic", "diff_hard4");
		RemoveByPrefix("prop_dynamic", "diff_hard5");
		RemoveByPrefix("prop_dynamic", "diff_hard6");
		RemoveByPrefix("prop_dynamic", "diff_hard7");
		RemoveByPrefix("prop_dynamic", "diff_hard8");
		RemoveByPrefix("prop_dynamic", "diff_hard9");

		RemoveByPrefix("trigger_progress_use", "spawn_1_hard1_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard2_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard3_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard4_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard5_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard6_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard7_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard8_trigger");
		RemoveByPrefix("trigger_progress_use", "spawn_1_hard9_trigger");
	}
	
}

void RemoveByPrefix(const char[] classname, const char[] partialName)
{
	char buffer[32];
	int e = -1;
	while ((e = FindEntityByClassname(e, classname)) != -1)
	{
		GetEntPropString(e, Prop_Data, "m_iName", buffer, sizeof(buffer));

		if (StrContains(buffer, partialName) == 0)
		{
			RemoveEntity(e);
		}
	}
}

int FindEntityByTargetame(int e, const char[] classname, const char[] targetname)
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