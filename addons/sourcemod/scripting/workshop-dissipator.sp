#include <sourcemod>

ConVar cvWorkshopID;
ConVar cvFastDownload;

public Plugin myinfo = {
    name        = "Incinerator",
    author      = "Dysphie",
    description = "",
    version     = "1.0.0",
    url         = ""
};

public void OnPluginStart()
{
	cvFastDownload = FindConVar("sv_downloadurl");
	cvWorkshopID = FindConVar("sv_workshop_map_id");
}

public void OnClientPostAdminCheck(int client)
{
	cvWorkshopID.ReplicateToClient(client, "-1");
	cvFastDownload.ReplicateToClient(client, "https://www.cia.gov/resources/fastdl/nmrih");
}