

#include <sourcemod>
#include <morecolors>
#include <sdktools_voice>
#include <basecomm>

GlobalForward g_SayText2Fwd;

public Plugin myinfo = {
    name        = "NMRiH Chat Processor",
    author      = "Dysphie",
    description = "",
    version     = "1.0.1",
    url         = ""
};

public void OnPluginStart()
{
	LoadTranslations("nmrihcp.phrases");
	g_SayText2Fwd = new GlobalForward("OnChatMessage", ET_Event, Param_CellByRef, Param_Cell, Param_String, Param_String);
	HookUserMessage(GetUserMessageId("SayText2"), OnSayText2, true);
}

Action OnSayText2(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{	
	int author = msg.ReadByte();
	if (!author) {
		return Plugin_Continue;
	}
	
	if (BaseComm_IsClientMuted(author) && !IsChatTrigger()) {
		return Plugin_Handled;
	}

	int showInChat = msg.ReadByte();

	char type[255];
	msg.ReadString(type, sizeof(type));

	if (!TranslationPhraseExists(type)) {
		return Plugin_Continue;
	}

	ArrayList recipients = new ArrayList();
	for (int i = 0; i < playersNum; i++) {
		// TODO: whitelist filtering
		recipients.Push(players[i]);
	}

	char authorName[255];
	msg.ReadString(authorName, sizeof(authorName));

	char content[255];
	msg.ReadString(content, sizeof(content));

	//StripColors(authorName);
	//StripColors(content);
	//PrintToServer("type: %s, author: %s, content: %s", type, authorName, content);

	// Ask other plugins if they want to modify us
	Call_StartForward(g_SayText2Fwd);
	Call_PushCellRef(author);
	Call_PushCell(recipients);
	Call_PushStringEx(authorName, sizeof(authorName), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushStringEx(content, sizeof(content), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Action result;
	Call_Finish(result);

	// If a plugin modified our data, we must cancel the current message and 
	// queue a new one to be sent when this usermessage is closed
	if (result == Plugin_Changed)
	{
		DataPack data = new DataPack();
		
		int numSerials = recipients.Length;
		if (numSerials > 0)
		{
			int[] serials = new int[numSerials];
			for (int i = 0; i < numSerials; i++) 
			{
				serials[i] = GetClientSerial(recipients.Get(i));
			}

			data.WriteCell(numSerials);
			data.WriteCellArray(serials, numSerials);
			data.WriteCell(author);
			data.WriteCell(showInChat);
			data.WriteString(type);
			data.WriteString(authorName);
			data.WriteString(content);
			
			RequestFrame(Frame_SendMessage, data);
		}

		result = Plugin_Handled;
	}

	delete recipients;
	return result;
}

void Frame_SendMessage(DataPack data)
{
	data.Reset();

	int numSerials = data.ReadCell();
	int[] serials = new int[numSerials];
	data.ReadCellArray(serials, numSerials);

	int author = data.ReadCell();
	bool showInChat = data.ReadCell();

	char type[255];
	data.ReadString(type, sizeof(type));

	char authorName[MAX_NAME_LENGTH];
	data.ReadString(authorName, sizeof(authorName));

	char content[255];
	data.ReadString(content, sizeof(content));

	//CPrintToChatAll("Frame_SendMessage: type: %s, author %s, content: %s", type, authorName, content);
	
	delete data;

	for (int i = 0; i < numSerials; i++)
	{
		int client = GetClientFromSerial(serials[i]);
		if (!client) {
			continue;
		}

		// Hide messages from people you've muted
		if (author != client && IsClientMuted(client, author)) {
			continue;
		}

		int langId = GetClientLanguage(client);

		char langCode[10];
		GetLanguageInfo(langId, langCode, sizeof(langCode));

		//PrintToServer("Getting %s in %s lang", type, langCode)

		char translated[255];
		Format(translated, sizeof(translated), "\x01%T", type, client, authorName, content);

		//PrintToServer("Translated input %s and %s -> %s", authorName, content, translated);
		
		Handle msg = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
		BfWrite bf = UserMessageToBfWrite(msg);
		bf.WriteByte(author);
		bf.WriteByte(showInChat);
		bf.WriteString(translated);

		//PrintToServer("Sending: %s", translated);
		bf.WriteString("");
		bf.WriteString("");
		bf.WriteString("");
		bf.WriteString("");
		EndMessage();
	}
}

enum
{
	COLOR_NORMAL = 1,
	COLOR_USEOLDCOLORS = 2,
	COLOR_PLAYERNAME = 3,
	COLOR_LOCATION = 4,
	COLOR_ACHIEVEMENT = 5,
	COLOR_CUSTOM = 6,		// Will use the most recently SetCustomColor()
	COLOR_HEXCODE = 7,		// Reads the color from the next six characters
	COLOR_HEXCODE_ALPHA = 8,// Reads the color and alpha from the next eight characters
	COLOR_MAX
};

void StripColors(char[] test)
{
	// Converts color control characters into control characters for the normal color
	for (int i = 0; test[i]; i++)
	{
		if (test[i] && test[i] < COLOR_MAX)
		{
			if ( test[i] == COLOR_HEXCODE || test[i] == COLOR_HEXCODE_ALPHA )
			{
				// mark the next seven or nine characters. one for the control character and six or eight for the code itself.
				int skip = test[i] == COLOR_HEXCODE ? 7 : 9;
				for ( int j = 0; j < skip && test[i+j]; j++)
				{
					test[i+j] = COLOR_NORMAL;
				}
			}
			else
			{
				test[i] = COLOR_NORMAL;
			}
		}
	}
}