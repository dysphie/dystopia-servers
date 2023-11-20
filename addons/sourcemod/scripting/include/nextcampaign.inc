/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod (C)2004-2014 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This file is part of the SourceMod/SourcePawn SDK.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#if defined _nextcampaign_included_
 #endinput
#endif
#define _nextcampaign_included_

/**
 * Sets SourceMod's internal nextcampaign.
 * Equivalent to changing sm_nextcampaign but with an added validity check.
 *
 * @param campaign           Next campaign to set.
 * @return              True if the nextcampaign was set, false if campaign was invalid.
 */
native bool SetNextCampaign(const char[] campaign);

/**
 * Returns SourceMod's internal nextcampaign.
 *
 * @param campaign           Buffer to store the nextcampaign name.
 * @param maxlen        Maximum length of the campaign buffer.
 * @return              True if a Map was found and copied, false if no nextcampaign is set (campaign will be unchanged).
 */
native bool GetNextCampaign(char[] campaign, int maxlen);

/**
 * Changes the current campaign and records the reason for the change with maphistory
 *
 * @param campaign           Map to change to.
 * @param reason        Reason for change.
 */
native void ForceChangeLevel(const char[] campaign, const char[] reason);

/**
 * Gets the current number of maps in the campaign history
 *
 * @return              Number of maps.
 */
native int GetMapHistorySize();

/**
 * Retrieves a campaign from the campaign history list.
 *
 * @param item          Item number. Must be 0 or greater and less than GetMapHistorySize().
 * @param campaign           Buffer to store the campaign name.
 * @param mapLen        Length of campaign buffer.
 * @param reason        Buffer to store the change reason.
 * @param reasonLen     Length of the reason buffer.
 * @param startTime     Time the campaign started.
 * @error               Invalid item number.
 */
native void GetCampaignHistory(int item, char[] campaign, int mapLen, char[] reason, int reasonLen, int &startTime);
