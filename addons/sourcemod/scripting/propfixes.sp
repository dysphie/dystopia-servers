
#include <sdkhooks>
#include <sdktools>

#define CLASSNAME_MAX 128

static const char PLAYER_PICKUP[] = "player_pickup";

int				  g_offset_originalCollisionGroup;	  // Offset of m_iOriginalCollisionGroup in CBaseEntity.
ArrayList		  g_carried_props;
ConVar			  g_qol_dropped_object_collision_fix;	 // Maintain an object's original collision properties even if multiple players try to pick it up.
ConVar			  g_qol_weaponized_object_fix;			 // Prevent exploit that allows carried physics props to damage players and zombies.

#define collisionGroup_CARRIED_OBJECT 34

public Plugin myinfo =
{
	name = "Prop Fixes (QOL Extract)",
	author = "Ryan & Dysphie",
	description = "",
	version = "",
	url = ""
};

enum struct PropCollisionData
{
	int entRef;			   // int - Ent reference
	int collisionGroup;	   // int - Original collision group
}

public void OnPluginStart()
{
	g_carried_props = new ArrayList(sizeof(PropCollisionData))
	GameData gamedata = new GameData("propfixes.games");

	g_qol_weaponized_object_fix = CreateConVar("qol_weaponized_object_fix", "1",
		"Prevent exploit that allows physics objects to damage players and zombies by being smashed into them.");

	g_qol_dropped_object_collision_fix = CreateConVar("qol_dropped_object_collision_fix", "1",
		"Ensure prop's original collision group is restored after players drop it. This prevents solid props becoming non-solid after dropping them.");

	g_offset_originalCollisionGroup	= gamedata.GetOffset("CPlayerPickupController::m_iOriginalCollisionGroup");
	if (g_offset_originalCollisionGroup == -1)
	{
		SetFailState("Failed to retrieve offset ")
	}

	delete gamedata;
}

void CachePropCollisionGroup(int player_pickup, int pickup)
{
	int originalCollisionGroup = GetEntData(player_pickup, g_offset_originalCollisionGroup, 4);

	int pickup_ref			   = EntIndexToEntRef(pickup);

	// Lookup original collision group.
	int index				   = g_carried_props.FindValue(pickup_ref, PropCollisionData::entRef);
	if (index != -1)
	{
		originalCollisionGroup = g_carried_props.Get(index, PropCollisionData::collisionGroup);
	}
	else
	{
		// Add new entry.
		PropCollisionData collision_tuple;
		collision_tuple.entRef		   = pickup_ref;
		collision_tuple.collisionGroup = originalCollisionGroup;
		g_carried_props.PushArray(collision_tuple);
	}
}

/**
 * Restore collision group used by an object before it was picked up. (ConVar)
 */
public void OnFrame_RestorePropCollisionGroup(int pickup_ref)
{
	int index = g_carried_props.FindValue(pickup_ref, PropCollisionData::entRef);
	if (index != -1)
	{
		int pickup = EntRefToEntIndex(pickup_ref);
		if (pickup != INVALID_ENT_REFERENCE && g_qol_dropped_object_collision_fix.BoolValue)
		{
			// Return object to its original collision group.
			int originalCollisionGroup = g_carried_props.Get(index, PropCollisionData::collisionGroup);
			SetEntityCollisionGroup(pickup, originalCollisionGroup);
		}

		RemoveArrayListElement(g_carried_props, index);
	}
}

/**
 * Called when player_pickup carried object is dropped.

 * Prevent exploit where carried physics objects can be used as weapons. (ConVar)
 *
 * Also ensures the prop returns to its original collision group. (ConVar)
 */
Action Hook_PreventWeaponizedProps(
	int		player_pickup,
	int		activator,
	int		caller,
	UseType use_type,
	float	value)
{
	if (use_type == Use_Off)
	{
		int pickup = GetEntPropEnt(player_pickup, Prop_Data, "m_attachedEntity");
		if (pickup != -1)
		{
			int pickup_ref = EntIndexToEntRef(pickup);

			// Anyone else holding it?
			if (IsEntityHeldByPlayer(pickup, activator))
			{
				RequestFrame(OnFrame_PreventWeaponizedProp, pickup_ref);
			}
			else
			{
				RequestFrame(OnFrame_RestorePropCollisionGroup, pickup_ref);
			}
		}
	}

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, PLAYER_PICKUP))
	{
		SDKHook(entity, SDKHook_SpawnPost, Hook_UnstickCarriedObject);
		SDKHook(entity, SDKHook_Use, Hook_PreventWeaponizedProps);
	}
}

int IsEntityHeldByPlayer(int entity, int to_ignore = -1)
{
	char classname[CLASSNAME_MAX];

	int	 player = 0;
	for (int i = 1; i < MaxClients && player == 0; ++i)
	{
		if (i != to_ignore && IsClientInGame(i) && IsPlayerAlive(i))
		{
			int use_entity = GetEntPropEnt(i, Prop_Send, "m_hUseEntity");
			if (use_entity != -1 && IsClassnameEqual(use_entity, classname, sizeof(classname), PLAYER_PICKUP) && GetEntPropEnt(use_entity, Prop_Data, "m_attachedEntity") == entity)
			{
				player = i;
			}
		}
	}
	return player;
}

/**
 * Quickly remove an element from ArrayList by swapping it with last element
 * and then popping the back.
 */
stock void RemoveArrayListElement(ArrayList list, int index)
{
	if (list && index >= 0 && index < list.Length)
	{
		int last = 0;
		if (list.Length > 1)
		{
			last = list.Length - 1;
			list.SwapAt(index, last);
		}
		list.Erase(last);
	}
}

/**
 * Retrieve edict's classname and compare it to a string.
 */
stock bool IsClassnameEqual(int entity, char[] classname, int classname_size, const char[] compare_to)
{
	GetEdictClassname(entity, classname, classname_size);
	return StrEqual(classname, compare_to);
}

/**
 * Set object to collision group that prevents it being used like a weapon. (ConVar)
 */
public void OnFrame_PreventWeaponizedProp(int pickup_ref)
{
	int index = g_carried_props.FindValue(pickup_ref, PropCollisionData::entRef);
	if (index != -1)
	{
		int pickup = EntRefToEntIndex(pickup_ref);
		if (pickup != INVALID_ENT_REFERENCE && g_qol_weaponized_object_fix.BoolValue)
		{
			// Prevent prop from being used as a weapon.
			SetEntityCollisionGroup(pickup, collisionGroup_CARRIED_OBJECT);
		}
		else
		{
			// Invalid pickup, we can safely remove this index.
			RemoveArrayListElement(g_carried_props, index);
		}
	}
}

/**
 * Wait one frame for player_pickup to initialize.
 */
public void Hook_UnstickCarriedObject(int player_pickup)
{
    RequestFrame(OnFrame_WatchCarriedObject, EntIndexToEntRef(player_pickup));
}



/**
 * Unstuck items grabbed by the player. Some maps have items that are otherwise
 * unobtainable.
 *
 * Store item's original collision group.
 */
public void OnFrame_WatchCarriedObject(int player_pickup_ref)
{
    int player_pickup = EntRefToEntIndex(player_pickup_ref);
    if (player_pickup != INVALID_ENT_REFERENCE)
    {
        int player = GetEntPropEnt(player_pickup, Prop_Send, "m_pPlayer");
        if (player > 0 && player <= MaxClients && IsClientInGame(player))
        {
            int pickup = GetEntPropEnt(player_pickup, Prop_Data, "m_attachedEntity");
            if (IsValidEdict(pickup))
            {
                CachePropCollisionGroup(player_pickup, pickup);
            }
        }
    }
}