#include <sdktools>
#include <sdkhooks>
#pragma semicolon 1;
#pragma newdecls required;

public void OnPluginStart()
{
	RegConsoleCmd("bot",blckserver);
	RegConsoleCmd("bot_forcefireweapon",blckserver);
	RegConsoleCmd("bot_forceattack2",blckserver);
	RegConsoleCmd("bot_forceattackon",blckserver);
	RegConsoleCmd("bot_flipout",blckserver);
	RegConsoleCmd("bot_defend",blckserver);
	RegConsoleCmd("bot_changeclass",blckserver);
	RegConsoleCmd("bot_selectweaponslot",blckserver);
	RegConsoleCmd("bot_dontmove",blckserver);
	RegConsoleCmd("bot_randomnames",blckserver);
	RegConsoleCmd("bot_saveme",blckserver);
	RegConsoleCmd("bot_jump",blckserver);
	RegConsoleCmd("bot_mimic",blckserver);
	RegConsoleCmd("bot_command",blckserver);
	RegConsoleCmd("bot_mimic_yaw_offset",blckserver);
	RegConsoleCmd("bot_kill",blckserver);
	RegConsoleCmd("bot_kick",blckserver);
	RegConsoleCmd("bot_changeteams",blckserver);
	RegConsoleCmd("bot_teleport",blckserver);
	RegConsoleCmd("bot_refill",blckserver);
	RegConsoleCmd("bot_warp_team_to_me",blckserver);
	RegConsoleCmd("bot_whack",blckserver);
	HookEventEx("player_spawn",OnPlayerSpawn,EventHookMode_Post);
	CreateTimer(1.0, resetdev, _, TIMER_REPEAT);
}

public Action blckserver(int client, int args)
{
	if (client == 0) return Plugin_Continue;
	return Plugin_Handled;
}

public void OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event,"userid"));
	CreateTimer(0.1,everyspawnpost,client,TIMER_FLAG_NO_MAPCHANGE);
	return;
}

public Action resetdev(Handle timer)
{
	for (int i = 1;i<MaxClients+1;i++)
	{
		if (IsValidEntity(i))
		{
			if (IsClientInGame(i))
			{
				if (HasEntProp(i,Prop_Send,"m_bIsPlayerADev"))
				{
					if (GetEntProp(i,Prop_Send,"m_bIsPlayerADev"))
					{
						char SteamID[32];
						GetClientAuthId(i,AuthId_Steam2,SteamID,sizeof(SteamID));
						LogMessage("%N IsPlayerADev %s",i,SteamID);
					}
					SetEntProp(i,Prop_Send,"m_bIsPlayerADev",0);
				}
				if (HasEntProp(i,Prop_Send,"m_bIsPlayerNicknine"))
				{
					if (GetEntProp(i,Prop_Send,"m_bIsPlayerNicknine"))
					{
						char SteamID[32];
						GetClientAuthId(i,AuthId_Steam2,SteamID,sizeof(SteamID));
						LogMessage("%N IsPlayerNicknine %s",i,SteamID);
					}
					SetEntProp(i,Prop_Send,"m_bIsPlayerNicknine",0);
				}
			}
		}
	}
}

public Action everyspawnpost(Handle timer, int client)
{
	if (IsValidEntity(client))
	{
		if (HasEntProp(client,Prop_Send,"m_bIsPlayerADev")) SetEntProp(client,Prop_Send,"m_bIsPlayerADev",0);
		if (HasEntProp(client,Prop_Send,"m_bIsPlayerNicknine")) SetEntProp(client,Prop_Send,"m_bIsPlayerNicknine",0);
	}
	else CreateTimer(0.1,everyspawnpost,client,TIMER_FLAG_NO_MAPCHANGE);
}