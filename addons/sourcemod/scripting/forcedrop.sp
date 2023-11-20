#include <morecolors>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
	name = "Force Drop Weapon",
	author = "Dysphie",
	description = "",
	version = "",
	url = ""
};

public void OnPluginStart()
{
	RegAdminCmd("sm_drop", Cmd_Cam, ADMFLAG_ROOT);
}

Action Cmd_Cam(int client, int args)
{
	char cmdTarget[MAX_TARGET_LENGTH];
	GetCmdArg(1, cmdTarget, sizeof(cmdTarget));

	char item[64];
	GetCmdArg(2, item, sizeof(item));

	int target = FindTarget(client, cmdTarget);
	if (target != -1)
	{
		DropWeapon(target, item);
	}

	return Plugin_Handled;
}

void DropWeapon(int client, const char[] wanted)
{
	int size = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	char itemName[11];

	for (int i; i < size; i++)
	{
		int item = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (item == -1)
			continue;
		
		GetEntityClassname(item, itemName, sizeof(itemName));

		if (StrContains(itemName, wanted) != -1)
		{
			SDKHooks_DropWeapon(client, item);
			break;
		}
	}
}