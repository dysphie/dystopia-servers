

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define NMR_MAXPLAYERS 9

public Plugin myinfo =
{
	name = "Cat Hired to Stare at You",
	author = "Dysphie",
	description = "",
	version = "",
	url = ""
};

int weaponSwitchTick[NMR_MAXPLAYERS+1];

#define IN_SHOVE 0x8000000


public void OnPluginStart()
{
	
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client)) {
			OnClientPutInServer(client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitched);
}

void OnWeaponSwitched(int client, int weapon)
{
	if (client != -1) 
	{
		weaponSwitchTick[client] = GetGameTickCount();
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if ((buttons & IN_SHOVE) && !(GetOldButtons(client) & IN_SHOVE))
	{
		int shoveTick = GetGameTickCount();
		int diff = shoveTick - weaponSwitchTick[client];
		if (diff == 1) 
		{
			buttons &= ~IN_SHOVE;
			LogMessage("%L shoved in %d ticks", client, diff);
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

int GetOldButtons(int client)
{
	return GetEntProp(client, Prop_Data, "m_nOldButtons");
}