#include <dhooks>
#include <sdkhooks>

#define DAMAGE_YES 2

public Plugin myinfo =
{
	name = "Cinematic God Mode Fix",
	author = "Dysphie",
	description = "Fix players not taking damage if they spawn during a cinematic",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	HookEntityOutput("nmrih_extract_preview", "OnEndFollow", OnCinematicEnd);
	HookEntityOutput("point_viewcontrol", "OnEndFollow", OnCinematicEnd);
}

void OnCinematicEnd(const char[] output, int caller, int activator, float delay)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			SetEntProp(i, Prop_Data, "m_takedamage", DAMAGE_YES);
		}
	}
}