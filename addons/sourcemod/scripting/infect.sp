#include <vscript_proxy>

public Plugin myinfo = {
    name        = "NMRiH Admin Tools",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};


public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	RegAdminCmd("sm_infect", Cmd_Infect, ADMFLAG_ROOT);
}

Action Cmd_Infect(int admin, int args)
{
	char cmdTarget[MAX_TARGET_LENGTH];
	GetCmdArg(1, cmdTarget, sizeof(cmdTarget));

	int silent = GetCmdArgInt(2);

	int target = FindTarget(admin, cmdTarget);

	if (target != -1)
	{
		SetEntProp(target, Prop_Send, "_vaccinated", false);
		RunEntVScript(target, "BecomeInfected()");

		if (!silent) {
			PrintToChatAll("%N infectó a %N", admin, target);
		}
	}

	return Plugin_Handled;
}