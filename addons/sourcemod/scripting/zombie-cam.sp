// TODO: Proper cleanup on plugin unloaded
// TODO: Map change handling?

#include <sdktools>
#include <sdkhooks>
#include <sourcemod>

#define EFL_DONTBLOCKLOS (1<<25)

public Plugin myinfo = {
    name        = "Zombie Spectators",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

#define MAX_EDICTS (1 << 11)

#pragma semicolon 1
#pragma newdecls required

#define NMR_MAXPLAYERS 9

bool isZombie[MAX_EDICTS+1];

Menu g_ZombieMenu[NMR_MAXPLAYERS];

StringMap g_Positions;

enum struct ZombiePosData
{
	float angles[3];
	float offset[3];
	char attachment[50];
}

enum struct ZombieCamera
{
	int client;
	int cameraRef;
	int zombieRef;

	// Attach our camera to a zombie's eyes
	void Spectate(int zombie)
	{
		AcceptEntityInput(this.cameraRef, "ClearParent");

		SetVariantString("!activator");
		AcceptEntityInput(this.cameraRef, "SetParent", zombie);

		char model[PLATFORM_MAX_PATH];
		GetEntityModel(zombie, model, sizeof(model));

		ZombiePosData data;
		g_Positions.GetArray(model, data, sizeof(data));
		
		if (data.attachment[0])
		{
			SetVariantString(data.attachment);
			AcceptEntityInput(this.cameraRef, "SetParentAttachment");
		}

		SetEntPropVector(this.cameraRef, Prop_Send, "m_angRotation", data.angles);
		SetEntPropVector(this.cameraRef, Prop_Send, "m_vecOrigin", data.offset);

		//TeleportEntity(this.cameraRef, .angles=data.angles);
		this.zombieRef = EntIndexToEntRef(zombie);
	}

	bool Create(int player)
	{
		if (this.IsValid()) {
			return true;
		}

		this.client = player;

		this.zombieRef = -1;
		this.cameraRef = -1;
		
		//int camera = CreateEntityByName("info_target");

		// TODO: don't block LOS
		int camera = CreateEntityByName("prop_dynamic_override");
		DispatchKeyValue(camera, "model", "models/blackout.mdl");
		DispatchKeyValue(camera, "spawnflags", "256");
		DispatchKeyValue(camera, "rendermode", "10");
		DispatchKeyValue(camera, "solid", "0");

		SetEntPropString(camera, Prop_Data, "m_iClassname", "zombie_camera");

		DispatchSpawn(camera);
		this.cameraRef = EntIndexToEntRef(camera);
		SetClientViewEntity(player, camera);

		AddEFlags(camera, EFL_DONTBLOCKLOS);

		return this.Switch();
	}

	void Destroy()
	{
		SafeRemoveEntity(this.cameraRef);
		this.cameraRef = -1;
		SetClientViewEntity(this.client, this.client);
	}

	bool IsValid()
	{
		bool result = this.cameraRef && IsValidEntity(this.cameraRef);
		return result;
	}

	bool Switch(bool reverse = false)
	{
		int curZombie = EntRefToEntIndex(this.zombieRef);

		int nextZombie = reverse ? GetPreviousZombie(curZombie) : GetNextZombie(curZombie);

		if (nextZombie == -1)
		{
			this.Destroy();
			return false;
		}

		if (nextZombie != curZombie) {
			this.Spectate(nextZombie);
		}
		
		return true;
	}

	int GetZombieIndex()
	{
		return this.zombieRef ? EntRefToEntIndex(this.zombieRef) : -1;
	}
}

void SafeRemoveEntity(int entity)
{
	int idx = EntRefToEntIndex(entity);

	if (idx < MaxClients) 
	{
		LogError("Tried to delete unsafe entity %d", idx);
		return;
	}

	RemoveEntity(entity);
}

bool IsAttachableZombie(int zombie)
{
	if (!isZombie[zombie]) {
		return false;
	}

	char model[PLATFORM_MAX_PATH];
	GetEntityModel(zombie, model, sizeof(model));
	return g_Positions.ContainsKey(model);
}

void GetEntityModel(int entity, char[] buffer, int maxlen)
{
	GetEntPropString(entity, Prop_Data, "m_ModelName", buffer, maxlen);
}

ZombieCamera g_ZombieCameras[NMR_MAXPLAYERS+1];

ConVar cvAllowAlive;

public void OnPluginStart()
{
	LoadTranslations("zombiecam.phrases");

	g_Positions = new StringMap();
	ParseConfig();

	cvAllowAlive = CreateConVar("sm_allow_alive_zombiecam", "0");

	RegAdminCmd("sm_reload_zombiecam_config", OnCmdReloadConfig, ADMFLAG_ROOT);
	RegConsoleCmd("sm_zcam", OnCmdZombieMenu);
	RegConsoleCmd("sm_zombie", OnCmdZombieMenu);

	RegConsoleCmd("zombie_spec", OnCmdSpec, "Enables zombie view");
	RegConsoleCmd("zombie_spec_stop", OnCmdExit, "Disables zombie view");
	RegConsoleCmd("zombie_spec_next", OnCmdNext, "Switch zombie view to the next available zombie");
	RegConsoleCmd("zombie_spec_prev", OnCmdPrev, "Switch zombie view to the last previewed zombie");

	// Late load handling
	int i = -1; 
	while((i = FindEntityByClassname(i, "npc_nmrih*")) != -1)
		isZombie[i] = true;

	AutoExecConfig(true, "zombiecam");

	HookEvent("player_spawn", Event_PlayerSpawn);
}

Action OnCmdReloadConfig(int client, int args)
{
	ParseConfig();
	ReplyToCommand(client, "Reloaded zombiecam config");
	return Plugin_Handled;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && IsClientInGame(client) && g_ZombieCameras[client].IsValid())
	{
		g_ZombieCameras[client].Destroy();
		delete g_ZombieMenu[client];
	}	
}

Action OnCmdZombieMenu(int client, int args)
{
	if (!CanUseCommand(client)) {
		return Plugin_Handled;
	}

	CreateZombieMenu(client);
	return Plugin_Handled;
}

void CreateZombieMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ZombieMenu);
	menu.SetTitle("%T", "Menu Title", client);

	char buffer[255];

	if (g_ZombieCameras[client].IsValid())
	{
		int zed = g_ZombieCameras[client].GetZombieIndex();
		menu.SetTitle("%T %T", "Menu Title", client, "Zombie ID", client, zed);	
		
		Format(buffer, sizeof(buffer), "%T", "Disable Camera", client);
		menu.AddItem("zombie_spec_stop", buffer);
	}
	else
	{	
		menu.SetTitle("%T", "Menu Title", client);

		Format(buffer, sizeof(buffer), "%T", "Enable Camera", client);
		menu.AddItem("zombie_spec", buffer);
	}

	// Format(buffer, sizeof(buffer), "%T", "Enable Camera", client);
	// menu.AddItem("sm_spec", buffer);

	// Format(buffer, sizeof(buffer), "%T", "Disable Camera", client);
	// menu.AddItem("sm_exit", buffer);

	Format(buffer, sizeof(buffer), "%T", "Next Zombie", client);
	menu.AddItem("zombie_spec_next", buffer);

	Format(buffer, sizeof(buffer), "%T", "Previous Zombie", client);
	menu.AddItem("zombie_spec_prev", buffer);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	g_ZombieMenu[client] = menu;
}

int MenuHandler_ZombieMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
		return 0;
	}

	if (action == MenuAction_Cancel)
	{
		g_ZombieMenu[param1] = null;
		return 0;
	}

	if (action == MenuAction_Select)
	{
		char selection[32];
		menu.GetItem(param2, selection, sizeof(selection));
		FakeClientCommand(param1, selection);
		CreateZombieMenu(param1);
	}

	return 0;
}



public void OnEntityCreated(int entity, const char[] classname)
{
	char NPC_PREFIX[] = "npc_nmrih_";

	if (entity > 0 && !strncmp(classname, NPC_PREFIX, sizeof(NPC_PREFIX)-1))
	{
		isZombie[entity] = true;
	}
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= 0 || !isZombie[entity])
		return;

	isZombie[entity] = false;

	for(int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (EntIndexToEntRef(entity) != g_ZombieCameras[i].zombieRef)
			continue;

		// We ran out of zeds, update the zombie menu
		if (!g_ZombieCameras[i].Switch()) {
			CreateZombieMenu(i);
		}
	}
}

public void OnClientDisconnected(int client)
{
	g_ZombieCameras[client].Destroy();
}

public Action OnCmdSpec(int client, int args)
{	
	if (!CanUseCommand(client)) {
		return Plugin_Handled;
	}

	if (!g_ZombieCameras[client].Create(client))
	{
		ReplyToCommand(client, "%t", "No Zombies Available");
	}

	return Plugin_Handled;
}

public Action OnCmdNext(int client, int args)
{
	if (!CanUseCommand(client)) {
		return Plugin_Handled;
	}

	if (!g_ZombieCameras[client].IsValid())
	{
		ReplyToCommand(client, "%t", "Zombie Camera Is Not Active");
		return Plugin_Handled;
	}

	g_ZombieCameras[client].Switch();
	return Plugin_Handled;
}

public Action OnCmdPrev(int client, int args)
{
	if (!CanUseCommand(client)) {
		return Plugin_Handled;
	}

	if (!g_ZombieCameras[client].IsValid())
	{
		ReplyToCommand(client, "%t", "Zombie Camera Is Not Active");
		return Plugin_Handled;
	}

	g_ZombieCameras[client].Switch(.reverse=true);
	return Plugin_Handled;
}

public Action OnCmdExit(int client, int args)
{
	if (!CanUseCommand(client)) {
		return Plugin_Handled;
	}

	if (!g_ZombieCameras[client].IsValid())
	{
		return Plugin_Handled;
	}

	g_ZombieCameras[client].Destroy();
	return Plugin_Handled;
}

bool CanUseCommand(int& client)
{
	if (!client) 
	{
		client = 1;
		return true;

		//ReplyToCommand(client, "In-game clients only");
		//return false;
	}

	if (IsPlayerAlive(client) && !cvAllowAlive.BoolValue) 
	{
		ReplyToCommand(client, "%t", "You Must Be Dead");
		return false;
	}

	return true;
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && g_ZombieCameras[i].IsValid())
		{
			g_ZombieCameras[i].Destroy();
		}
	}
}

int GetNextZombie(int currentEnt)
{
	int result = -1;
	currentEnt++;

	int arraySize = sizeof(isZombie);
	for (int i = currentEnt; i < currentEnt + arraySize; i++) 
	{
		int index = i % arraySize;
		if (IsAttachableZombie(index)) 
		{
			result = index;
			break;
		}
	}

	return result; // We did not find any true value in the array
}

int GetPreviousZombie(int currentEnt)
{
	currentEnt--;
	int arraySize = sizeof(isZombie);

	for (int i = currentEnt; i >= currentEnt - arraySize; i--)
	{
		int index = (i + arraySize) % arraySize;
		if (IsAttachableZombie(index)) {
			return index;
		}
	}

	return -1; // We did not find any true value in the array
}

void ParseConfig()
{	
	g_Positions.Clear();
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/zombiecam.cfg");

	KeyValues kv = new KeyValues(path);
	if (!kv.ImportFromFile(path)) 
	{
		SetFailState("No config file %s", path);
	}

	if (kv.GotoFirstSubKey())
	{
		do
		{
			ZombiePosData data;
			kv.GetSectionName(path, sizeof(path));

			kv.GetVector("offset", data.offset);
			kv.GetVector("angles", data.angles);
			kv.GetString("attachment", data.attachment, sizeof(data.attachment));

			g_Positions.SetArray(path, data, sizeof(data));
		}
		while(kv.GotoNextKey());
	}

	delete kv;
}

void AddEFlags(int entity, int newFlags)
{
	int flags = GetEntProp(entity, Prop_Data, "m_iEFlags");
	SetEntProp(entity, Prop_Data, "m_iEFlags", flags | newFlags);
}