
enum SpeedType
{
	Speed_InventoryNormal,
	Speed_InventoryHalf,
	Speed_InventoryFull,
	Speed_WalkBackwards,
	Speed_MaxTypes
};

/**
 * Overrides a client's maximum speed
 *
 * @param client		Player's index.
 * @param ratio			Speed ratio. This cannot exceed the corresponding cvar's bounds.
 * @param speedType		Type of speed to override.
 * @return 			 	True if the value was clamped to the cvar's bounds. False otherwise.
 * @error				Invalid client index, or client not in-game.
 */
native bool NMR_OverrideMaxSpeed(int client, float ratio, SpeedType speedType);

/**
 * Removes a client's speed override.
 *
 * @param client		Player's index.
 * @param speedType		Type of speed.
 * @error				Invalid client index, or client not in-game.
 */
native void NMR_RemoveMaxSpeedOverride(int client, SpeedType speedType);

/**
 * Checks if a client's speed override is active.
 *
 * @param client		Player's index.
 * @param speedType		Type of speed.
 * @return 			 	True if the value is being overridden. False otherwise.
 */
native bool NMR_IsMaxSpeedOverridden(int client, SpeedType speedType);