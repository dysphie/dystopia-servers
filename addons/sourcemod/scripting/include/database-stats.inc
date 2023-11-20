
#if defined _database_stats_included_
  #endinput
#endif
#define _database_stats_included_

forward void OnNewTimeRecord(const char[] mapName, const char[] modeName, 
  const char[] newHolderName, float newTimeSeconds, bool previousRecordExisted, 
  const char[] oldHolderName, float oldTimeSeconds, int division);
