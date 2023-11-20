#include <sourcemod>
#include <ripext>
#include <database-stats>

ConVar cvWebHook;

public Plugin myinfo =
{
	name = "Records Discord Notifications",
	author = "Dysphie",
	description = "",
	version = "",
	url = ""
};

enum
{
	Mode_Casual,
	Mode_Pro,
	Mode_NoDmg,
	Mode_MAX
}

public void OnPluginStart()
{
	cvWebHook = CreateConVar("record_notif_webhook", "", .flags = FCVAR_PROTECTED | FCVAR_NEVER_AS_STRING );
}

void StripBackticks(char[] str, int maxlen)
{
	ReplaceString(str, maxlen, "`", "");
}

void StripSquiggly(char[] str, int maxlen)
{
	ReplaceString(str, maxlen, "~", "");
}

void ReqFinished(HTTPResponse response, any value, const char[] error)
{
	PrintToServer("status: %d, error: %s", response.Status, error);
}

public void OnNewTimeRecord(const char[] mapName, const char[] modeName, const char[] newHolderName, float newTimeSeconds, 
	bool previousRecordExisted, const char[] oldHolderName, float oldTimeSeconds, int division)
{
	char divName[][] = {
		"Casual",
		"Pro",
		"Sin Daño"
	}

	char url[1024];
	cvWebHook.GetString(url, sizeof(url))
	HTTPRequest req	 = new HTTPRequest(url);
	
	//HTTPRequest req	 = new HTTPRequest("https://discord.com/api/webhooks/1138302157922242561/DVaRQkr_c6irqyadzh84oxfxmTYy8sttSMRpYgUhQ7ZGgDveJPAl8HIglLw_phnkpkAb?wait=true");
	JSONObject	msg = new JSONObject();

	char newHolderNameEscaped[MAX_NAME_LENGTH];
	strcopy(newHolderNameEscaped, sizeof(newHolderNameEscaped), newHolderName);
	StripBackticks(newHolderNameEscaped, sizeof(newHolderNameEscaped));

	char newTimeStr[32];
	SecondsToHumanTime(newTimeSeconds, newTimeStr, sizeof(newTimeStr));

	char content[255];

	if (previousRecordExisted && oldHolderName[0]) // fixme: oldholdername check is a bandaid because previousRecordExisted wrongly returns true
	{
		char oldHolderNameEscaped[MAX_NAME_LENGTH];
		strcopy(oldHolderNameEscaped, sizeof(oldHolderNameEscaped), oldHolderName);
		StripBackticks(oldHolderNameEscaped, sizeof(oldHolderNameEscaped));
		StripSquiggly(oldHolderNameEscaped, sizeof(oldHolderNameEscaped));

		char oldTimeStr[32];
		SecondsToHumanTime(oldTimeSeconds, oldTimeStr, sizeof(oldTimeStr));

		float timeDiff = oldTimeSeconds - newTimeSeconds;

		char timeDiffStr[32];
		SecondsToHumanTime(timeDiff, timeDiffStr, sizeof(timeDiffStr));

		FormatEx(content, sizeof(content),
			"🏁 **%s (%s) - [%s]** 🏆 `%s` batió el **récord de tiempo (%s)** de ~~`%s`~~ por %s!",
			mapName, modeName, newTimeStr, newHolderNameEscaped, divName[division], oldHolderNameEscaped, timeDiffStr);
	}
	else
	{
		FormatEx(content, sizeof(content),
			"🏁 **%s (%s) - [%s]** 🏆 `%s` obtuvo el primer **récord de tiempo (%s)**!",
			mapName, modeName, newTimeStr, newHolderNameEscaped, divName[division]);
	}

	msg.SetString("content", content);
	req.Post(view_as<JSON>(msg), ReqFinished);
	delete msg;
}

void SecondsToHumanTime(float value, char[] buffer, int maxlen, bool includeMilli = true)
{
	bool neg = value < 0.0;
	if (neg) {
		value = -value;
	}

	int secs    = RoundToFloor(value);
	int milli   = RoundToFloor((value - float(secs)) * 1000);
	int minutes = secs / 60;
	int seconds = secs % 60;

	if (includeMilli) {
		Format(buffer, maxlen, "%s%02d:%02d.%03d",  neg ? "-" : "", minutes, seconds, milli);
	} else {
		Format(buffer, maxlen, "%s%02d:%02d",  neg ? "-" : "", minutes, seconds);
	}
}
