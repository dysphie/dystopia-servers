#include <sourcemod>
#include <morecolors>

Menu g_MainMenu;

bool joinedGame[MAXPLAYERS+1];
char MENU_ITEM_PREFIX[] = "menu_";

public Plugin myinfo = {
    name        = "Home Menu",
    author      = "Dysphie",
    description = "The server's home menu with shortcuts to various commands",
    version     = "1.0.0",
    url         = ""
};

public void OnClientDisconnect(int client)
{
	joinedGame[client] = false;
}

public void OnPluginStart()
{
	LoadTranslations("hub_menu.phrases.txt");

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/hub_menu.cfg");

	KeyValues kv = new KeyValues("Menu");
	if (!kv.ImportFromFile(path)) {
		SetFailState("Failed to open %s", path);
	}

	g_MainMenu = BuildMenuRecursive(kv);

	RegConsoleCmd("sm_menu", Cmd_MainMenu);
	
	AddCommandListener(Cmd_Joingame, "joingame");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			CPrintToChat(i, "%t", "hint");
		}
	}
}

Action Cmd_Joingame(int client, const char[] command, int argc)
{
	if (!joinedGame[client]) {
		joinedGame[client] = true;
		CPrintToChat(client, "%t", "hint");
	}
	return Plugin_Continue;
}


Action Cmd_MainMenu(int client, int args)
{
	g_MainMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

Menu BuildMenuRecursive(KeyValues kv)
{
	Menu menu = new Menu(MenuHandler_CommandMenu, MenuAction_DisplayItem);

	if (kv.GotoFirstSubKey(false))
	{
		do
		{
			char description[64];
			kv.GetSectionName(description, sizeof(description));
			StrToLower(description);

			//PrintToServer("description: %s", description);

			if (KvIsSection(kv))
			{
				Menu child = BuildMenuRecursive(kv);
				char handleStr[20];
				Format(handleStr, sizeof(handleStr), "%s%x", MENU_ITEM_PREFIX, child);
				menu.AddItem(handleStr, description);
			}
			else
			{
				char command[32]; 
				kv.GetString(NULL_STRING, command, sizeof(command));
				menu.AddItem(command, description);
			}
		}
		while (kv.GotoNextKey(false))

		kv.GoBack();
	}

	if (!menu.ItemCount)
	{
		menu.AddItem("", "nothing here");
	}

	return menu;
}

void StrToLower(char[] str)
{
	for (int i = 0; str[i]; i++) {
		str[i] = CharToLower(str[i]);
	}
}

bool KvIsSection(KeyValues kv)
{
	if (kv.GotoFirstSubKey(false))
	{
		kv.GoBack();
		return true;
	}

	return false;
}

int MenuHandler_CommandMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char selection[32];
			menu.GetItem(param2, selection, sizeof(selection));

			if (strncmp(selection, MENU_ITEM_PREFIX, sizeof(MENU_ITEM_PREFIX)-1) == 0)
			{
				Menu childMenu = view_as<Menu>(StringToInt(selection[5], 16));
				childMenu.Display(param1, MENU_TIME_FOREVER);
			}
			else
			{
				//PrintToServer("Issuing %s as %N", selection, param1);
				FakeClientCommand(param1, "say /%s", selection);
			}
		}

		case MenuAction_DisplayItem:
		{
			char selection[32], display[256];
			menu.GetItem(param2, selection, sizeof(selection), _, display, sizeof(display));

			if (TranslationPhraseExists(display))
			{
				Format(display, sizeof(display), "%T", display, param1);
				return RedrawMenuItem(display);
			}
			
			return 0;
		}
	}

	return 0;
}