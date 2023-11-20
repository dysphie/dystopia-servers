#include <sourcemod>
#include <base64>
#include <morecolors>

#define MAX_MESSAGE_LEN 255
#define MAX_ACCOUNTID_LEN 12
#define MAX_MENU_INFO MAX_ACCOUNTID_LEN+1+MAX_MESSAGE_LEN

#define NMR_MAXPLAYERS 9

Database g_DB;

public Plugin myinfo =
{
    name = "Chat Messages",
    author = "Dysphie",
    description = "",
    version = "",
    url = ""
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_recentmessages", Cmd_RecentMessages);
    RegConsoleCmd("sm_savedmessages", Cmd_SavedMessages);
    RegConsoleCmd("sm_messages", Cmd_Messages, "Save and share chat messages");
    RegConsoleCmd("sm_mensajes", Cmd_Messages, "Guarda y comparte mensajes");
    RegConsoleCmd("sm_msj", Cmd_Messages, "Guarda y comparte mensajes");
    RegConsoleCmd("sm_msg", Cmd_Messages, "Save and share chat messages");
    Database.Connect(DatabaseConnectResult, "storage-local");
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
    if (!client || IsChatTrigger()) {
        return;
    }

    int senderID = GetClientDatabaseID(client);
    if (!senderID) {
        return;
    }

    char query[256];
    g_DB.Format(query, sizeof(query), "INSERT INTO message (sender_id, content) VALUES (%d, '%s');", senderID, sArgs);
    g_DB.Query(QueryResult_SaveMessage, query);
}

int GetClientDatabaseID(int client)
{
    if (!IsClientAuthorized(client)) return 0;
    return GetSteamAccountID(client);
}

void QueryResult_SaveMessage(Database db, DBResultSet results, const char[] error, any data)
{
    if (!db || !results || error[0]) {
        LogError("QueryResult_SaveMessage: %s", error);
    }
}

void DatabaseConnectResult(Database db, const char[] error, any data)
{
    if (!db) {
        SetFailState("Couldn't connect to database");
    }

    g_DB = db;
    CreateTables();
}

void CreateTables()
{
    Transaction txn = new Transaction();

    char query[2048];
    g_DB.Format(query, sizeof(query), 
        "CREATE TABLE IF NOT EXISTS message (" ...
            "id INTEGER PRIMARY KEY, " ...
            "sender_id INTEGER NOT NULL, " ...
            "content TEXT NOT NULL, " ...
            "timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP " ...
        ");"
    )
    txn.AddQuery(query);

    g_DB.Format(query, sizeof(query), 
        "CREATE TABLE IF NOT EXISTS saved_message (" ...
            "saver_id INTEGER NOT NULL REFERENCES player (id), " ...
            "msg_id INTEGER NOT NULL REFERENCES message (id), " ...
            "timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP " ...
        ");"
    )
    txn.AddQuery(query);

    g_DB.Execute(txn, TxnSuccess_CreateTables, TxnFail_CreateTables);
}

void TxnFail_CreateTables(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    SetFailState("TxnFail_CreateTables [%d]: %s", failIndex, error);
}

void TxnSuccess_CreateTables(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{

}

Action Cmd_Messages(int client, int args)
{
    Messages(client);
    return Plugin_Handled;
}

void Messages(int client)
{
    Menu menu = new Menu(MenuHandler_Messages);
    menu.AddItem("recent", "Guardar mensaje");
    menu.AddItem("saved", "Compartir mensaje guardado");
    menu.AddItem("delete", "Borrar mensaje guardado (Pronto)", ITEMDRAW_DISABLED);
    menu.Display(client, MENU_TIME_FOREVER);
}

int MenuHandler_Messages(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_End:
        {
            delete menu;
        }

        case MenuAction_Select:
        {  
            char info[32];
            menu.GetItem(param2, info, sizeof(info));

            if (StrEqual(info, "recent")) {
                GetRecentMessages(param1);
            } else if (StrEqual(info, "saved")) {
                GetSavedMessages(param1);
            }
        }
    }

    return 0;  
}

Action Cmd_SavedMessages(int client, int args)
{
    GetSavedMessages(client);
    return Plugin_Handled;
}

void GetSavedMessages(int client)
{
    int saverID = GetClientDatabaseID(client);
    if (!saverID) {
        return;
    }
    
    char query[2048];
    g_DB.Format(query, sizeof(query), 
        "SELECT m.content, p.name FROM saved_message sm " ...
        "JOIN message m ON sm.msg_id = m.id " ...
        "JOIN player p ON p.id = m.sender_id " ... 
        "WHERE sm.saver_id = %d " ...
        "ORDER BY m.timestamp DESC " ...
        "LIMIT 500;", saverID);
    g_DB.Query(QueryResult_GetSavedMessages, query, GetClientSerial(client));
}

Action Cmd_RecentMessages(int client, int args)
{
    GetRecentMessages(client);
    return Plugin_Handled;
}

void GetRecentMessages(int client)
{
    int saverID = GetClientDatabaseID(client);

    char query[2048];
    g_DB.Format(query, sizeof(query), 
        "SELECT m.id, m.content, p.name, " ...
        "CASE WHEN sm.saver_id IS NULL THEN 0 ELSE 1 END as saved " ...
        "FROM message m " ...
        "JOIN player p ON p.id = m.sender_id " ... 
        "LEFT JOIN saved_message sm ON sm.msg_id = m.id AND sm.saver_id = %d " ...
        "ORDER BY m.timestamp DESC " ...
        "LIMIT 15;", saverID);
    g_DB.Query(QueryResult_GetRecentMessages, query, GetClientSerial(client));

}

void QueryResult_GetSavedMessages(Database db, DBResultSet results, const char[] error, int clientSerial)
{
    if (!db || !results || error[0]) 
    {
        LogError("QueryResult_FetchMesages: %s", error);
        return;
    }

    int client = GetClientFromSerial(clientSerial);
    if (!client || !IsClientInGame(client)) {
        return;
    }
    // Reference: SELECT m.content, p.name FROM message 

    char message[MAX_MESSAGE_LEN], author[MAX_NAME_LENGTH];
    char messageEncoded[2048], authorEncoded[2048];

    Menu menu = new Menu(MenuHandler_ShareMessage);
    menu.SetTitle("Compartir Mensaje Guardado");
    while (results.FetchRow()) 
    {
        results.FetchString(0, message, sizeof(message));
        EncodeBase64(messageEncoded, sizeof(messageEncoded), message);
        results.FetchString(1, author, sizeof(author));
        EncodeBase64(authorEncoded, sizeof(authorEncoded), author);

        char info[2048], display[255];
        Format(info, sizeof(info), "%s %s", messageEncoded, authorEncoded);
        Format(display, sizeof(display), "%s: %s", author, message);
        menu.AddItem(info, display);
    }

    menu.ExitBackButton = true;

    if (menu.ItemCount <= 0) {
        menu.AddItem("", "No tienes mensajes guardados", ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}


void QueryResult_GetRecentMessages(Database db, DBResultSet results, const char[] error, int clientSerial)
{
    if (!db || !results || error[0]) 
    {
        LogError("QueryResult_FetchMesages: %s", error);
        return;
    }

    int client = GetClientFromSerial(clientSerial);
    if (!client || !IsClientInGame(client)) {
        return;
    }
    // Reference: SELECT m.content, p.name FROM message 

    char message[MAX_MESSAGE_LEN], author[MAX_NAME_LENGTH];

    Menu menu = new Menu(MenuHandler_SaveRecentMessage);
    menu.SetTitle("Guardar Mensaje");
    while (results.FetchRow()) 
    {
        int id = results.FetchInt(0);

        char info[12], display[255];
        IntToString(id, info, sizeof(info));

        results.FetchString(1, message, sizeof(message));
        results.FetchString(2, author, sizeof(author));

        Format(display, sizeof(display), "%s: %s", author, message);

        int style = ITEMDRAW_DEFAULT;
        if (results.FetchInt(3) != 0) {
            style = ITEMDRAW_DISABLED;
            StrCat(display, sizeof(display), " (Guardado)");
        }

        menu.AddItem(info, display, style);
    }

    menu.ExitBackButton = true;

    if (menu.ItemCount <= 0) {
        menu.AddItem("", "No hay mensajes recientes", ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}


int MenuHandler_SaveRecentMessage(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_End:
        {
            if (param1 != MenuEnd_Selected) {
                delete menu;
            }
        }

        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack) {
                Messages(param1);
            }
        }

        case MenuAction_Select:
        {
            char msgID[12];
            menu.GetItem(param2, msgID, sizeof(msgID));

            int saverID = GetClientDatabaseID(param1);
            if (!saverID) {
                return 0;
            }

            char query[256];
            g_DB.Format(query, sizeof(query), 
                "INSERT INTO saved_message (saver_id, msg_id) " ...
                    "VALUES (%d, %s);", saverID, msgID 
            );

            g_DB.Query(QueryResult_SaveRecentMessage, query, GetClientSerial(param1));
        }
    }

    return 0;
}

void QueryResult_SaveRecentMessage(Database db, DBResultSet results, const char[] error, int clientSerial)
{
    if (!db || !results || error[0]) {
        LogError("QueryResult_SaveRecentMessage: %s", error);
    }

    int client = GetClientFromSerial(clientSerial);
    if (!client || !IsClientInGame(client)) {
        return;
    }

    GetRecentMessages(client);
}

int MenuHandler_ShareMessage(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_End:
        {
            if (param1 != MenuEnd_Selected) {
                delete menu;
            }
        }

        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack) {
                Messages(param1);
            }
        }

        case MenuAction_Select:
        {
            char info[MAX_MENU_INFO];
            menu.GetItem(param2, info, sizeof(info));

            char messageEncoded[2048], authorEncoded[1024];
            int cursor = SplitString(info, " ", messageEncoded, sizeof(messageEncoded));
            strcopy(authorEncoded, sizeof(authorEncoded), info[cursor]);

            char message[MAX_MESSAGE_LEN], author[MAX_NAME_LENGTH];
            DecodeBase64(message, sizeof(message), messageEncoded);
            DecodeBase64(author, sizeof(author), authorEncoded);

            CPrintToChatAll("{hotpink}%N{lightpink} compartió {lightskyblue}%s: %s", param1, author, message);
            menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
        }
    }

    return 0;
}
