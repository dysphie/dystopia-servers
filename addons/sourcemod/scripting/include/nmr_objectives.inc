/** Double-include prevention */
#if defined _nmr_objectives_included
  #endinput
#endif
#define _nmr_objectives_included

// ObjectiveManager is a class that manages the objectives of a mission.
// It can create, update, complete and clear objectives, as well as get information about them.
methodmap ObjectiveManager
{
	// CompleteCurrentObjective completes the current objective and optionally sets a forced extraction zone.
	// @param forcedExtractZone The name of the extraction zone to use, or "" for none.
	public static native void CompleteCurrentObjective(const char[] forcedExtractZone = NULL_STRING);
	
	// Returns the ObjectiveBoundary object of the current objective, or null if there is none.
	// @return An ObjectiveBoundary object or null.
	public static native ObjectiveBoundary GetCurrentObjectiveBoundary();
	
	// Clear clears all the objectives and resets the ObjectiveManager state.
	public static native void Clear();
	
	// Finish finishes the mission and shows the end screen.
	public native void Finish();
	
	// GetObjectiveById returns the Objective object with the given id, or null if there is none.
	// @param id The id of the objective to get.
	// @return An Objective object or null.
	public static native Objective GetObjectiveById(int id);
	
	// GetObjectiveByIndex returns the Objective object at the given index in the objective list, or null if there is none.
	// @param index The index of the objective to get, starting from 0.
	// @return An Objective object or null.
	public static native Objective GetObjectiveByIndex(int index);
	
	// GetObjectiveByName returns the Objective object with the given name, or null if there is none.
	// @param name The name of the objective to get.
	// @return An Objective object or null.
	public static native Objective GetObjectiveByName(const char[] name);
	
	// IsCompleted returns true if all the objectives are completed, false otherwise.
	// @return A bool value indicating if all the objectives are completed.
	public static native bool IsCompleted();
	
	// IsFailed returns true if any of the objectives are failed, false otherwise.
	// @return A bool value indicating if any of the objectives are failed.
	public static native bool IsFailed();
	
	// StartNextObjective starts the next objective in the list, if there is any.
	public static native void StartNextObjective();
	
	// UpdateObjectiveBoundaries updates the boundaries of all the objectives based on their entities and links.
	public static native void UpdateObjectiveBoundaries();
}

// ObjectiveBoundary is a class that represents a boundary for an objective.
// It can be a trigger, a marker, a zone or any other entity that defines where an objective takes place.
methodmap ObjectiveBoundary
{
	// Finish finishes the boundary and removes any effects or markers associated with it.
	public native void Finish();
	
	// Start starts the boundary and adds any effects or markers associated with it.
	public native void Start();
}

// Objective is a class that represents an objective of a mission.
// It can have a name, a description, a list of entities and links, and a boundary.
methodmap Objective
{	
	// GetDescription returns the description of this objective, or "" if there is none.
	// @param buffer The buffer to store the description in.
	// @param maxlen The maximum length of the buffer.
	// @return The number of bytes written to the buffer, or 0 if there is no description. 
	public native int GetDescription(char[] buffer, int maxlen);
	
	// GetEntity returns the name and index of an entity in this objective's list by its index in the list, or "" and -1 if there is none. 
	// @param index The index of the entity in the list, starting from 0. 
	// @param buffer The buffer to store the name of the entity in. 
	// @param maxlen The maximum length of the buffer. 
	// @return The index of the entity in the game world, or -1 if there is no such entity. 
	public native ArrayList GetEntityList();
	
	// GetLink returns the id of a link in this objective's list by its index in the list, or -1 if there is none. 
	// A link is an id that connects two objectives together and defines how they are related. 
	// For example, a link can indicate that an objective must be completed before another one can start, or that an objective is optional, etc. 
	// @param index The index of the link in the list, starting from 0. 
	// @return The id of the link, or -1 if there is no such link. 
	public native int GetLink(int index);
	
	// GetName returns the name of this objective, or "" if there is none. 
	// @param buffer The buffer to store the name in. 
	// @param maxlen The maximum length of the buffer. 
	// @return The number of bytes written to the buffer, or 0 if there is no name. 
	public native int GetName(char[] buffer, int maxlen);
	
	// GetObjectiveBoundary returns the ObjectiveBoundary object of this objective, or null if there is none. 
	// @return An ObjectiveBoundary object or null. 
	public native ObjectiveBoundary GetObjectiveBoundary();
	
	// HasLink returns true if this objective has a link with the given id, false otherwise. 
	// @param linkId The id of the link to check for. 
	// @return A bool value indicating if this objective has the link. 
	public native bool HasLink(int linkId);
	
	// IsEndObjective returns true if this objective is the last one in the mission, false otherwise. 
	// @return A bool value indicating if this objective is the end objective. 
	public native bool IsEndObjective();
	
	// UpdateBoundary updates the boundary of this objective based on its entities and links. 
	public native void UpdateBoundary();
}
