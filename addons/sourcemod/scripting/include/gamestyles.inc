#if defined _gamestyles_included_
  #endinput
#endif
#define _gamestyles_included_


enum
{
	STYLE_CASUAL = 0,
	STYLE_RANKED  = (1 << 1),
	STYLE_NODMG	  = (1 << 2),
	STYLE_NOSHOVE = (1 << 3),
	STYLE_BAN = (1 << 4),
	STYLE_LOWSTAM = (1 << 5),
	MAX_STYLES = 6
}

char styleNames[][] = 
{
	"STYLE_CASUAL",
	"STYLE_RANKED",
	"STYLE_NODMG",
	"STYLE_NOSHOVE",
	"STYLE_BAN",
	"STYLE_LOWSTAM"
}

native int GetClientStyles(int client);

stock bool GetStylePhrase(int style, char[] buffer, int maxlen)
{
	if (!style) 
	{
		strcopy(buffer, maxlen, "STYLE_CASUAL");
		return true;
	}

	for (int i = 1; i < MAX_STYLES; i++)
	{
		if ((1 << i) == style)
		{
			strcopy(buffer, maxlen, styleNames[i]);
			return true;
		}
	}

	return false;
}