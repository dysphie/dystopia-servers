#include <sourcemod>
#include <regex>
#include <morecolors>

public Plugin myinfo =
{
	name		= "Assignable Name Colors",
	author		= "Dysphie",
	description = "",
	version		= "",
	url			= ""
};

#define NMR_MAXPLAYERS 9
#define MAX_COLORS	   2

Database g_DB;

#define COLOR_NONE		0
#define COLOR_LEFT		1
#define COLOR_RIGHT		2

#define MAX_HEXCODE_LEN 8

int		  g_EditingColorIndex[NMR_MAXPLAYERS + 1] = { -1, ... };
bool	  g_TypingColorHex[NMR_MAXPLAYERS + 1]	  = { false, ... };
char	  g_CachedName[NMR_MAXPLAYERS + 1][MAX_NAME_LENGTH];
ArrayList g_Colors[NMR_MAXPLAYERS + 1] = { null, ... };
ArrayList g_DefaultColors = null;

Regex	  g_HexRegex = null;

ConVar cvMaxColors = null;

enum struct DatabaseColor
{
	int id;
	char hex[MAX_HEXCODE_LEN];
}

public void OnPluginStart()
{
	cvMaxColors = CreateConVar("max_name_colors", "15");

	g_DefaultColors = new ArrayList(ByteCountToCells(MAX_HEXCODE_LEN));

	for (int i = 1; i < sizeof(g_Colors); i++) {
		g_Colors[i] = new ArrayList(sizeof(DatabaseColor));
	}

	HookEvent("player_changename", Event_PlayerChangeName);

	LoadTranslations("neocolors.phrases");

	Database.Connect(DatabaseConnectResult, "storage-local");

	g_HexRegex = new Regex("^#?([0-9a-fA-F]{6})$");

	//RegAdminCmd("sm_become", Cmd_Pretend, ADMFLAG_ROOT);
	RegConsoleCmd("sm_color", Cmd_Color);
	RegConsoleCmd("sm_namecolor", Cmd_Color);

	LoadDefaultColors();
}

void LoadDefaultColors()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/colors.ini");

	File f = OpenFile(path, "r");
	if (!f) {
		SetFailState("No %s", path);
	}

	char hex[MAX_HEXCODE_LEN];
	char line[256];
	while (f.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		if (StringToHex(line, hex, sizeof(hex)))
		{
			g_DefaultColors.PushString(hex);
		}
	}

	PrintToServer("Loaded %d colors", g_DefaultColors.Length);
	delete f;
}

void DatabaseConnectResult(Database db, const char[] error, any data)
{
	if (!db || error[0])
	{
		SetFailState("DatabaseConnectResult: %s", error);
	}

	g_DB = db;
	CreateTables();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("GetColoredName", Native_GetColoredName);
	return APLRes_Success;
}

any Native_GetColoredName(Handle plugin, int numParams)
{
	int	 client = GetNativeCell(1);

	char clientName[MAX_NAME_LENGTH];

	if (HasColoredName(client))
	{
		Format(clientName, sizeof(clientName), "%s", g_CachedName[client]);
	}
	else
	{
		GetClientName(client, clientName, sizeof(clientName));
	}

	SetNativeString(2, clientName, GetNativeCell(3));
	return 0;
}

public void OnClientDisconnect(int client)
{
	g_TypingColorHex[client]	= false;
	g_EditingColorIndex[client] = -1;
	g_Colors[client].Clear();
	g_CachedName[client] = "";
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_TypingColorHex[client])
	{
		return Plugin_Continue;
	}

	g_TypingColorHex[client] = false;

	char  hex[MAX_HEXCODE_LEN];
	if (!StringToHex(sArgs, hex, sizeof(hex)))
	{
		CPrintToChat(client, "%t", "Invalid Custom Color");
		return Plugin_Stop;
	}

	InsertDatabaseColor(client, hex);
	return Plugin_Stop;
}

bool StringToHex(const char[] str, char[] hex, int maxlen)
{
	//PrintToServer("StringToHex %s", str);
	if (g_HexRegex.Match(str) <= 0)
	{
		return false;
	}

	g_HexRegex.GetSubString(1, hex, maxlen);

	// PrintToServer("StringToHex: %s => %s", str, hex);
	return true;
}

void InsertDatabaseColor(int client, const char[] hex)
{
	int accID = GetSteamAccountID(client);
	if (!accID)
	{
		return;
	}

	char query[1024];
	g_DB.Format(query, sizeof(query),
				"INSERT INTO name_color_new (player_id, hex)" ... "VALUES (%d, '%s');",
				accID, hex);

	DataPack data = new DataPack();
	data.WriteCell(GetClientSerial(client));
	data.WriteString(hex);
	g_DB.Query(QueryResult_InsertDatabaseColor, query, data);
}

void UpdateDatabaseColor(int client, int colorID, const char[] hex)
{
	// Update cache
	int colorIndex = g_Colors[client].FindValue(colorID, DatabaseColor::id);
	if (colorIndex != -1) 
	{
		DatabaseColor color;
		g_Colors[client].GetArray(colorIndex, color);
		strcopy(color.hex, sizeof(color.hex), hex);
		g_Colors[client].SetArray(colorIndex, color);

		ComputeCachedName(client, g_Colors[client]);
		
		PrintNamePreview(client);
	}

	// Update database
 	int accID = GetSteamAccountID(client);
	if (!accID)
	{
		return;
	}

	char query[256];
	g_DB.Format(query, sizeof(query),
			"UPDATE name_color_new SET hex = '%s'" ... "WHERE player_id = %d AND id = %d;",
			hex, accID, colorID);


	g_DB.Query(QueryResult_UpdateDatabaseColor, query, GetClientSerial(client)); 
}

void RemoveDatabaseColor(int client, int colorID)
{
	//PrintToServer("RemoveDatabaseColor");
 	int accID = GetSteamAccountID(client);
	if (!accID)
	{
		return;
	}

	// Update local cache
	int colorIndex = g_Colors[client].FindValue(colorID, DatabaseColor::id);
	if (colorIndex != -1) {
		g_Colors[client].Erase(colorIndex);
	}
	
	ComputeCachedName(client, g_Colors[client]);
	PrintNamePreview(client);

	char query[256];
	g_DB.Format(query, sizeof(query),
		"DELETE FROM name_color_new WHERE player_id = %d AND id = %d;",
		accID, colorID);


	g_DB.Query(QueryResult_RemoveDatabaseColor, query, GetClientSerial(client)); 
}

void PrintNamePreview(int client)
{
	CPrintToChat(client, "%t", "New Name Preview", g_CachedName[client]);
}

void QueryResult_RemoveDatabaseColor(Database db, DBResultSet results, const char[] error, any data)
{
	// todo
}

void QueryResult_UpdateDatabaseColor(Database db, DBResultSet results, const char[] error, any data)
{
	// todo
}

void CacheDatabaseColors(int client)
{
	g_Colors[client].Clear();

	int accID = GetSteamAccountID(client);
	if (!accID) {
		return;
	}

	char query[512];
	g_DB.Format(query, sizeof(query),
				"SELECT id, hex FROM name_color_new WHERE player_id = %d ORDER BY date_added ASC; ", accID);

	g_DB.Query(QueryResult_GetColors, query, GetClientSerial(client));

	// PrintToServer(query);
}

void QueryResult_GetColors(Database db, DBResultSet results, const char[] error, int clientSerial)
{
	if (!db || !results || error[0])
	{
		SetFailState("QueryResult_GetColors: %s", error);
	}

	int client = GetClientFromSerial(clientSerial);

	if (!client) {
		return;
	}

	g_Colors[client].Clear();
	DatabaseColor color;

	while (results.FetchRow())
	{
		color.id = results.FetchInt(0);
		results.FetchString(1, color.hex, sizeof(color.hex));
		g_Colors[client].PushArray(color);
	}

	ComputeCachedName(client, g_Colors[client]);
}

void ComputeCachedName(int client, ArrayList colors)
{
	//PrintToServer("Computing %d color name", colors.Length);

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	char richName[MAX_NAME_LENGTH];
	ApplyGradient(name, colors, richName, sizeof(richName));

	SetCachedName(client, richName);
}

void SetCachedName(int client, const char[] name)
{
	// CPrintToChatAll("Cached: %s", g_CachedName[client]);
	strcopy(g_CachedName[client], sizeof(g_CachedName[]), name);
}

public void Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client && IsClientInGame(client))
	{
		CacheDatabaseColors(client);
	}
}

void Menu_ColorOptions(int client)
{
	int colorIndex = g_EditingColorIndex[client];

	Menu menu = new Menu(MenuHandler_ColorOptions);

	if (colorIndex != -1)
	{
		menu.SetTitle("%T", "Menu Title - Edit Color", client, colorIndex + 1);
		AddMenuItemFormatted(menu, "remove", _, "%T", "Remove", client);
	}
	else
	{
		menu.SetTitle("%T", "Menu Title - Add Color", client, g_Colors[client].Length + 1);
	}

	// AddMenuItemFormatted(menu, "default", _, "%T", "Default", client);
	AddMenuItemFormatted(menu, "custom", _, "%T", "Custom", client);

	char buffer[255];
	int maxColors = g_DefaultColors.Length;
	char display[255];
	for (int i = 0; i < maxColors; i++)
	{
		g_DefaultColors.GetString(i, buffer, sizeof(buffer));
		TranslateHex(buffer, client, display, sizeof(display));
		menu.AddItem(buffer, display);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

void AddMenuItemFormatted(Menu menu, const char[] info, int style = 0, char[] format, any ...)
{
	char display[255];
	VFormat(display, sizeof(display), format, 5);
	menu.AddItem(info, display, style);
}

int MenuHandler_ColorOptions(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Select:
		{
			int	 client	   = param1;
			int	 selection = param2;

			char info[32];
			menu.GetItem(selection, info, sizeof(info));

			int colorIndex = g_EditingColorIndex[client];

			if (StrEqual(info, "custom"))
			{
				g_TypingColorHex[client] = true;
				PrintToChat(client, "%t", "Type Custom Color");
			}
			else if (StrEqual(info, "remove"))
			{
				DatabaseColor color;
				g_Colors[client].GetArray(colorIndex, color);
				RemoveDatabaseColor(client, color.id);
				Menu_Colors(client);
			}
			else if (StrEqual(info, "default"))
			{
			}
			else
			{
				if (colorIndex != -1)
				{
					DatabaseColor color;
					g_Colors[client].GetArray(colorIndex, color);
					UpdateDatabaseColor(client, color.id, info);
					Menu_Colors(client);
				}
				else
				{
					InsertDatabaseColor(client, info);
				}
			}

			// Menu_Colors(client);
		}
	}
	return 0;
}

// void DecodeOkLab(const char[] str, float lab[3])
// {
// 	char buffer[3][32];
// 	ExplodeString(str, ",", buffer, sizeof(buffer), sizeof(buffer[]));

// 	for (int i = 0; i < 3; i++) {
// 		lab[i] = StringToFloat(buffer[i]);
// 	}
// }

// void EncodeOkLab(float lab[3], char[] str, int maxlen)
// {
// 	FormatEx(str, maxlen, "%f,%f,%f", lab[0], lab[1], lab[2]);
// }

void OkLabToHex(float lab[3], char[] hex, int maxlen)
{
	float rgb[3];
	OKLabToRGB(lab, rgb);
	RGBToHex(rgb, hex, maxlen);
}

void QueryResult_InsertDatabaseColor(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if (!db || !results || error[0])
	{
		LogError("QueryResult_InsertDatabaseColor: %s", error);
		delete data;
		return;
	}

	int id = results.InsertId;
	if (id <= 0) 
	{
		delete data;
		return;
	}

	data.Reset();

	int client = GetClientFromSerial(data.ReadCell());
	if (!client || !IsClientInGame(client)) 
	{
		delete data;
		return;
	}
	
	DatabaseColor color;
	data.ReadString(color.hex, sizeof(color.hex));
	color.id = id;
	delete data;
 
	g_Colors[client].PushArray(color);
	ComputeCachedName(client, g_Colors[client]);
	PrintNamePreview(client);

	Menu_Colors(client);
}

void Menu_Colors(int client)
{
	Menu menu = new Menu(MenuHandler_Colors);
	menu.SetTitle("%T", "Menu Title - Colors", client);

	int	  numColors = g_Colors[client].Length;

	char  info[12];
	char  text[255];
	
	DatabaseColor color;

	for (int i = 0; i < numColors; i++)
	{
		g_Colors[client].GetArray(i, color);
		IntToString(i, info, sizeof(info));

		TranslateHex(color.hex, client, text, sizeof(text));
		menu.AddItem(info, text);
	}

	int style = ITEMDRAW_DEFAULT;
	if (numColors > cvMaxColors.IntValue) {
		style = ITEMDRAW_DISABLED;
	}

	AddMenuItemFormatted(menu, "add", style, "%T", "Add Color", client);
	menu.Display(client, MENU_TIME_FOREVER);
}

void TranslateHex(char[] hex, int lang, char[] buffer, int maxlen)
{
	if (TranslationPhraseExists(hex)) {
		Format(buffer, maxlen, "%T", hex, lang);
	} else {
		Format(buffer, maxlen, "#%s", hex);
	}
}

int MenuHandler_Colors(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Select:
		{
			int	 client	   = param1;
			int	 selection = param2;

			char info[12];
			menu.GetItem(selection, info, sizeof(info));

			if (StrEqual(info, "add"))
			{
				g_EditingColorIndex[client] = -1;
				Menu_ColorOptions(client);
			}
			else
			{
				g_EditingColorIndex[client] = StringToInt(info);
				Menu_ColorOptions(param1);
			}
		}
	}
	return 0;
}

void CreateTables()
{
	char query[1024];
	g_DB.Format(query, sizeof(query),
				"CREATE TABLE IF NOT EXISTS name_color_new (" ... 
					"id INTEGER PRIMARY KEY, " ... 
					"player_id INTEGER NOT NULL , " ... 
					"hex TEXT NOT NULL, " ... 
					"date_added TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)");

	g_DB.Query(QueryResult_CreateTables, query);
}

public void OnClientPostAdminCheck(int client)
{
	if (g_DB)
	{
		CacheDatabaseColors(client);
	}
}

void QueryResult_CreateTables(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		SetFailState("QueryResult_CreateTables: %s", error);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i))
		{
			CacheDatabaseColors(i);
		}
	}
}

Action Cmd_Color(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}

	Menu_Colors(client);
	return Plugin_Handled;
}

bool HexToOkLab(const char[] hex, float lab[3])
{
	float rgb[3];
	if (!HexToRGB(hex, rgb))
	{
		return false;
	}

	RGBToOKLab(rgb, lab);
	return true;
}

// void RandomLab(float lab[3])
// {
// 	lab[0] = GetRandomFloat(0.0, 1.0);
// 	lab[1] = GetRandomFloat(0.0, 0.5);
// 	lab[2] = GetRandomFloat(0.0, 360.0);
// }

// Action Cmd_Gradient(int client, int args)
// {
// 	// Create an arraylist of colors
// 	ArrayList colors = new ArrayList(3);
	
// 	// Add red, blue, green and yellow to the arraylist
// 	float lblue[3] = {0.76, -0.14, -0.19};
// 	float lpink[3] = {0.82, 0.15, 0.05};
// 	float white[3] = {1.0, 0.0, 0.0};
	
// 	colors.PushArray(lblue, sizeof(lblue));
// 	colors.PushArray(lpink, sizeof(lpink));
// 	colors.PushArray(white, sizeof(white));
// 	colors.PushArray(lpink, sizeof(lpink));
// 	colors.PushArray(lblue, sizeof(lblue));
	
// 	// Call the StringGradient function with a sample string
// 	char outputString[MAX_NAME_LENGTH];
// 	ApplyGradient("🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚🚚", 
//         colors, outputString, sizeof(outputString));
	
// 	// Print the output string
// 	PrintToChatAll("%s", outputString);

//     delete colors;
//     return Plugin_Handled;
// }

// Action Cmd_LabToRgb(int client, int args)
// {
// 	float lab[3];
// 	lab[0] = GetCmdArgFloat(1);
// 	lab[1] = GetCmdArgFloat(2);
// 	lab[2] = GetCmdArgFloat(3);

// 	float rgb[3];
// 	OKLabToRGB(lab, rgb);

// 	ReplyToCommand(client, "LAB(%f %f %f) => RGB(%f %f %f)",
// 				   lab[0], lab[1], lab[2], rgb[0], rgb[1], rgb[2]);

// 	return Plugin_Handled;
// }

// Action Cmd_RgbToLab(int client, int args)
// {
// 	float rgb[3];
// 	rgb[0] = GetCmdArgFloat(1);
// 	rgb[1] = GetCmdArgFloat(2);
// 	rgb[2] = GetCmdArgFloat(3);

// 	float lab[3];
// 	RGBToOKLab(rgb, lab);

// 	ReplyToCommand(client, "RGB(%f %f %f) => LAB(%f %f %f)",
// 				   rgb[0], rgb[1], rgb[2],
// 				   lab[0], lab[1], lab[2]);

// 	return Plugin_Handled;
// }

// float GammaToLinear(float c)
// {
// 	if (c >= 0.04045)
// 		return Pow((c + 0.055) / 1.055, 2.4);
// 	else
// 		return c / 12.92;
// }

float LinearToGamma(float c)
{
	if (c >= 0.0031308)
		return 1.055 * Pow(c, 1.0 / 2.4) - 0.055;
	else
		return 12.92 * c;
}

void RGBToOKLab(float rgb[3], float lab[3])
{
	float r = rgb[0] / 255;
	float g = rgb[1] / 255;
	float b = rgb[2] / 255;

	float l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
	float m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
	float s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

	l		= CubeRoot(l);
	m		= CubeRoot(m);
	s		= CubeRoot(s);

	lab[0]	= l * 0.2104542553 + m * 0.7936177850 + s * -0.0040720468;
	lab[1]	= l * 1.9779984951 + m * -2.4285922050 + s * 0.4505937099;
	lab[2]	= l * 0.0259040371 + m * 0.7827717662 + s * -0.8086757660;
}

void OKLabToRGB(float lab[3], float rgb[3])
{
	float l = lab[0] + lab[1] * 0.3963377774 + lab[2] * 0.2158037573;
	float m = lab[0] + lab[1] * -0.1055613458 + lab[2] * -0.0638541728;
	float s = lab[0] + lab[1] * -0.0894841775 + lab[2] * -1.2914855480;

	l		= Pow(l, 3.0);
	m		= Pow(m, 3.0);
	s		= Pow(s, 3.0);

	float r = (l * 4.0767416621 + m * -3.3077115913 + s * 0.2309699292);
	float g = (l * -1.2684380046 + m * 2.6097574011 + s * -0.3413193965);
	float b = (l * -0.0041960863 + m * -0.7034186147 + s * 1.7076147010);

	// Convert linear RGB values returned from oklab math to sRGB for our use before returning them:
	r		= 255 * LinearToGamma(r);
	g		= 255 * LinearToGamma(g);
	b		= 255 * LinearToGamma(b);

	r		= clamp(r, 0.0, 255.0);
	g		= clamp(g, 0.0, 255.0);
	b		= clamp(b, 0.0, 255.0);

	rgb[0]	= r;
	rgb[1]	= g;
	rgb[2]	= b;
}

public any clamp(any value, any min, any max)
{
	return value < min ? min : (value > max ? max : value);
}

float CubeRoot(float x)
{
	if (x == 0.0)
		return 0.0;

	float sign	 = (x > 0.0) ? 1.0 : -1.0;
	float absX	 = FloatAbs(x);
	float result = Pow(absX, 1.0 / 3.0);
	return sign * result;
}

bool HexToRGB(const char[] str, float rgb[3])
{
	char hex[MAX_HEXCODE_LEN];
	if (!StringToHex(str, hex, sizeof(hex)))
	{
		return false;
	}

	int hexInt = StringToInt(hex, 16);
	rgb[0]	   = (float)((hexInt >> 16) & 0xFF);
	rgb[1]	   = (float)((hexInt >> 8) & 0xFF);
	rgb[2]	   = (float)((hexInt)&0xFF);

	// PrintToServer("HexToRGB: %s => %s", hex, StrVec(rgb));

	return true;
}

void RGBToHex(float rgb[3], char[] hexstr, int size)
{
	int r = RoundToNearest(rgb[0]);
	int g = RoundToNearest(rgb[1]);
	int b = RoundToNearest(rgb[2]);

	FormatEx(
		hexstr,
		size,
		"%06X",
		((r & 0xFF) << 16) | ((g & 0xFF) << 8) | ((b & 0xFF)));
}

// float startRgb[3], endRgb[3];
// HexToRGB(startHex, startRgb);
// HexToRGB(endHex, endRgb);

// float startOkLab[3], endOkLab[3];
// RGBToOKLab(startRgb, startOkLab);
// RGBToOKLab(endRgb, endOkLab);

void ApplyGradient(const char[] trueStr, ArrayList colors, char[] outputString, int outputStringLen)
{
	int numColors = colors.Length;

	if (numColors <= 0) 
	{
		strcopy(outputString, outputStringLen, trueStr);
		return;
	}

	if (numColors == 1)
	{
		DatabaseColor color;
		colors.GetArray(0, color, sizeof(color));
		Format(outputString, outputStringLen, "\x07%s%s\x01", color.hex, trueStr);
		return;
	}

	char str[255];
	strcopy(str, sizeof(str), trueStr);
	ShortenToDoable(str);

	int	 numSteps = CountCharacters(str);

	// PrintToServer("Must go from %s to %s in %d steps", StrVec(okLabStart), StrVec(okLabEnd), numSteps);

	char newStr[MAX_NAME_LENGTH];

	int	 j			= 0;
	int	 skipAmount = 0;
	int	 newStrLen	= 0;

	for (int p = 0; p < MAX_NAME_LENGTH - 1; p++)
	{
		if (str[p] == '\0')
		{
			break;
		}

		if (skipAmount > 0)
		{
			newStr[newStrLen++] = str[p];
			skipAmount--;
			continue;
		}

		float v = (float)(j) / (numSteps - 1);

		float curLab[3];

		// Find the two colors that v is between and interpolate them
		float colorStep	 = 1.0 / (float)(numColors - 1);
		int	  colorIndex = RoundToFloor(v / colorStep);
		float colorT	 = (v - colorIndex * colorStep) / colorStep;

		DatabaseColor colorStart;
		DatabaseColor colorEnd;

		colors.GetArray(colorIndex, colorStart);

		//PrintToServer("[%d] %s", colorIndex, StrVec(okLabStart));

		if (colorIndex == colors.Length - 1)
		{
			colors.GetArray(colorIndex, colorEnd);
		}
		else {
			colors.GetArray(colorIndex + 1, colorEnd);
		}

		float okLabStart[3], okLabEnd[3];
		HexToOkLab(colorStart.hex, okLabStart);
		HexToOkLab(colorEnd.hex, okLabEnd);

		curLab[0] = (1.0 - colorT) * okLabStart[0] + colorT * okLabEnd[0];
		curLab[1] = (1.0 - colorT) * okLabStart[1] + colorT * okLabEnd[1];
		curLab[2] = (1.0 - colorT) * okLabStart[2] + colorT * okLabEnd[2];

		char hex[MAX_HEXCODE_LEN];
		OkLabToHex(curLab, hex, sizeof(hex));

		// If this is the start of a multi-byte character, skip coloring the rest of its bytes or we'll corrupt it
		skipAmount = IsCharMB(str[p]) - 1;

		if (newStrLen + 8 >= MAX_NAME_LENGTH - 1)
		{
			break;
		}

		newStr[newStrLen++] = '\x07';
		newStr[newStrLen++] = hex[0];
		newStr[newStrLen++] = hex[1];
		newStr[newStrLen++] = hex[2];
		newStr[newStrLen++] = hex[3];
		newStr[newStrLen++] = hex[4];
		newStr[newStrLen++] = hex[5];
		newStr[newStrLen++] = str[p];

		j++;
	}

	newStr[newStrLen] = '\x01';

	strcopy(outputString, outputStringLen, newStr);
}

void ShortenToDoable(char[] str)
{
	int newStrLen  = 0;
	int skipAmount = 0;

	// Do a dummy run to see how much we can actually do before running out of chars
	for (int i = 0; str[i]; i++)
	{
		if (skipAmount > 0)
		{
			newStrLen++;
			skipAmount--;
			continue;
		}

		skipAmount = IsCharMB(str[i]) - 1;

		if (newStrLen + 8 >= MAX_NAME_LENGTH - 1)
		{
			str[i] = '\0';
			return;
		}

		newStrLen += 8;
	}
}

// void ApplyGradient(const char[] inputString, float okLabStart[3], float okLabEnd[3], char[] outputString, int outputStringLen)
// {
//     int inputStringLen = strlen(inputString);
//     char[] buffer = new char[outputStringLen];
//     int j = 0;
//     int maxColorBytes = 5;
//     int colorByteInterval = inputStringLen / maxColorBytes;
//     for (int i = 0; i < inputStringLen; i++)
//     {
//         if (i % colorByteInterval == 0 && maxColorBytes > 0)
//         {
//             float v = (float)(i) / (inputStringLen - 1);
//             float curLab[3];
//             curLab[0] = (1 - v) * okLabStart[0] + v * okLabEnd[0];
//             curLab[1] = (1 - v) * okLabStart[1] + v * okLabEnd[1];
//             curLab[2] = (1 - v) * okLabStart[2] + v * okLabEnd[2];
//             float rgb[3];
//             OKLabToRGB(curLab, rgb);
//             char hex[8];
//             RGBToHex(rgb, hex, sizeof(hex));
//             if (j + 8 + 1 <= outputStringLen)
//             {
//                 buffer[j++] = '\x07';
//                 buffer[j++] = hex[0];
//                 buffer[j++] = hex[1];
//                 buffer[j++] = hex[2];
//                 buffer[j++] = hex[3];
//                 buffer[j++] = hex[4];
//                 buffer[j++] = hex[5];
//                 maxColorBytes--;
//             }
//         }
//         buffer[j++] = inputString[i];
//         if (j >= outputStringLen)
//         {
//             break;
//         }
//     }
//     buffer[j] = '\0';
//     strcopy(outputString, outputStringLen, buffer);
// }

bool HasColoredName(int client)
{
	return g_CachedName[client][0];
}
// void test()
// {
//     float okLabStart[3];
//     float okLabEnd[3];
//     RGBToOKLab({255.0, 0, 0}, okLabStart);
//     RGBToOKLab({0, 255.0, 0}, okLabEnd);

//     PrintToServer("lab start = %s", StrVec(okLabStart));
//     PrintToServer("lab end = %s", StrVec(okLabEnd));

//     int N = 10;

//     for (int i = 0; i < N; i++)
//     {
//         float v = (float)(i) / (N - 1);  // Perform floating-point division

//         float curLab[3];

//         curLab[0] = (1 - v) * okLabStart[0] + v * okLabEnd[0];
//         curLab[1] = (1 - v) * okLabStart[1] + v * okLabEnd[1];
//         curLab[2] = (1 - v) * okLabStart[2] + v * okLabEnd[2];

//         PrintToServer("[v = %f] lab mid = %s", v, StrVec(curLab));

//         float rgb[3];
//         OKLabToRGB(curLab, rgb);

//         char hex[8];  // Increased size to accommodate "#RRGGBB" format
//         RGBToHex(rgb[0], rgb[1], rgb[2], hex, sizeof(hex));
//         PrintToServer(hex);

//         //PrintToChatAll("\x07%02X%02X%02XHELLO", rgb[0], rgb[1], rgb[2]);
//     }
// }

// char[] StrVec(float vec[3])
// {
// 	char str[32];
// 	FormatEx(str, sizeof(str), "%f %f %f", vec[0], vec[1], vec[2]);
// 	return str;
// }

// void LerpVector(float start[3], float end[3], float result[3], float amount)
// {
// 	for (int i = 0; i < 3; i++)
// 	{
// 		result[i] = start[i] + (end[i] - start[i]) * amount;
// 	}
// }

#include <nmrih-cp>

public Action OnChatMessage(int& author, ArrayList recipients, char[] authorName, char[] message)
{
	// CPrintToChatAll("OnChatMessage => %s (cached: %s)", authorName, g_CachedName[author]);
	if (author && HasColoredName(author))
	{
		strcopy(authorName, MAX_NAME_LENGTH, g_CachedName[author]);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

int CountCharacters(const char[] str)
{
	int count = 0;
	for (int i = 0; str[i] != '\0'; i++)
	{
		if (IsCharMB(str[i]) == 0)
		{
			count++;
		}
		else {
			count++;
			i += IsCharMB(str[i]) - 1;
		}
	}
	return count;
}