#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude <SteamWorks>
#tryinclude <updater>
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#define PLUGIN_VERSION "1.00"
#define UPDATE_URL "https://raw.githubusercontent.com/Balimbanana/SM-LambdaFortress/master/addons/sourcemod/lfmiscfixesupdater.txt"

#pragma semicolon 1;
#pragma newdecls required;

float LastCmdRestrict[128];

public Plugin myinfo =
{
	name = "LFCoopMiscFixes",
	author = "Balimbanana",
	description = "Fixes issues in LFE.",
	version = PLUGIN_VERSION,
	url = "https://github.com/Balimbanana/SM-LambdaFortress"
}

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
	RegConsoleCmd("kickall", blckserver);
	RegConsoleCmd("kick", blckserver);
	RegConsoleCmd("kickid", blckserver);
	
	// Prevent spam of create/remove vehicle
	RegConsoleCmd("lfe_createvehicle", LFECreateVehicle);
	
	HookEventEx("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	CreateTimer(1.0, resetdev, _, TIMER_REPEAT);
	
	if (GetMapHistorySize() > -1)
	{
		for (int i = 1; i < MaxClients+1; i++)
		{
			if (IsValidEntity(i))
			{
				SDKHookEx(i, SDKHook_OnTakeDamage, OnTakeDamage);
			}
		}
		int iEntity = -1;
		while ((iEntity = FindEntityByClassname(iEntity, "npc_metropolice")) != INVALID_ENT_REFERENCE)
		{
			if (IsValidEntity(iEntity))
			{
				SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnCombineNPCTakeDamage);
			}
		}
		iEntity = -1;
		while ((iEntity = FindEntityByClassname(iEntity, "npc_combine_s")) != INVALID_ENT_REFERENCE)
		{
			if (IsValidEntity(iEntity))
			{
				SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnCombineNPCTakeDamage);
			}
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name,"updater",false))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void Updater_OnPluginUpdated()
{
	// Reload this plugin on update
	ReloadPlugin(INVALID_HANDLE);
}

public Action blckserver(int client, int args)
{
	if (client == 0) return Plugin_Continue;
	return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
	CreateTimer(5.0, ApplyHooks, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action ApplyHooks(Handle timer, int client)
{
	if (IsClientConnected(client))
	{
		if (IsClientInGame(client) && IsPlayerAlive(client))
		{
			SDKHookEx(client, SDKHook_OnTakeDamage, OnTakeDamage);
		}
		else
		{
			CreateTimer(1.0, ApplyHooks, client, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	static char szClassname[32];
	if (IsValidEntity(attacker))
	{
		GetEntityClassname(attacker, szClassname, sizeof(szClassname));
		if ((StrEqual(szClassname, "func_platrot", false)) || (StrEqual(szClassname, "func_door", false)))
		{
			if (HasEntProp(victim, Prop_Data, "m_hGroundEntity"))
			{
				int hGroundEntity = GetEntPropEnt(victim, Prop_Data, "m_hGroundEntity");
				if (hGroundEntity != attacker) return Plugin_Continue;
			}
			float vecOrigin[3];
			if (HasEntProp(victim, Prop_Data, "m_vecAbsOrigin")) GetEntPropVector(victim, Prop_Data, "m_vecAbsOrigin",vecOrigin);
			else if (HasEntProp(victim, Prop_Data, "m_vecOrigin")) GetEntPropVector(victim, Prop_Data, "m_vecOrigin",vecOrigin);
			vecOrigin[2]+=15.0;
			TeleportEntity(victim, vecOrigin, NULL_VECTOR, NULL_VECTOR);
			damage = 0.0;
			return Plugin_Changed;
		}
	}
	
	// This damage type and amount is caused by object that you are holding teleports
	if ((damage == 1000.0) && (damagetype == 8192))
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	
	// This damage comes from certain func_physbox's
	if (HasEntProp(attacker, Prop_Data, "m_hPhysicsAttacker"))
	{
		int hPhyAttacker = GetEntPropEnt(attacker, Prop_Data, "m_hPhysicsAttacker");
		if ((hPhyAttacker < MaxClients+1) && (hPhyAttacker > 0))
		{
			if ((HasEntProp(attacker, Prop_Data, "m_iTeamNum")) && (HasEntProp(victim, Prop_Data, "m_iTeamNum")))
			{
				if (GetEntProp(attacker, Prop_Data, "m_iTeamNum") == GetEntProp(victim, Prop_Data, "m_iTeamNum"))
				{
					damage = 0.0;
					return Plugin_Changed;
				}
			}
		}
	}
	
	// Prevent damage from players holding enemy turrets and manhacks
	GetEntityClassname(inflictor, szClassname, sizeof(szClassname));
	if ((StrEqual(szClassname, "npc_turret_floor", false)) || (StrEqual(szClassname, "npc_manhack", false)))
	{
		if (HasEntProp(inflictor, Prop_Data, "m_bCarriedByPlayer"))
		{
			if ((GetEntProp(inflictor, Prop_Data, "m_bCarriedByPlayer") != 0) || ((attacker < MaxClients+1) && (attacker > 0)))
			{
				damage = 0.0;
				return Plugin_Changed;
			}
		}
		if (HasEntProp(inflictor, Prop_Data, "m_bHeld"))
		{
			if (GetEntProp(inflictor, Prop_Data, "m_bHeld") != 0)
			{
				damage = 0.0;
				return Plugin_Changed;
			}
		}
	}
	else if (StrEqual(szClassname, "simple_physics_prop", false))
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	else if ((StrEqual(szClassname, "prop_vehicle_jeep", false)) || (StrEqual(szClassname, "prop_vehicle_airboat", false)))
	{
		// Prevent damage taken from unmanned vehicles, this prevents players taking damage from lfe_createvehicle
		if (HasEntProp(attacker, Prop_Data, "m_hPlayer"))
		{
			if (!IsValidEntity(GetEntPropEnt(attacker, Prop_Data, "m_hPlayer")))
			{
				damage = 0.0;
				return Plugin_Changed;
			}
		}
	}
	
	// Fall damage prevented while holding portalgun
	if (damagetype == 32)
	{
		if (HasEntProp(victim, Prop_Data, "m_hActiveWeapon"))
		{
			int hActiveWeapon = GetEntPropEnt(victim, Prop_Data, "m_hActiveWeapon");
			if (IsValidEntity(hActiveWeapon))
			{
				GetEntityClassname(hActiveWeapon, szClassname, sizeof(szClassname));
				if (StrContains(szClassname, "weapon_portalgun", false) != -1)
				{
					damage = 0.0;
					return Plugin_Changed;
				}
			}
		}
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int iEntity, const char[] szClassname)
{
	if ((StrEqual(szClassname, "npc_metropolice", false)) || (StrEqual(szClassname, "npc_combine_s", false)))
	{
		SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnCombineNPCTakeDamage);
	}
	
	return;
}

public Action OnCombineNPCTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if ((IsValidEntity(attacker)) && (IsValidEntity(inflictor)))
	{
		// Fixes running over combine, normally you just stop dead in your tracks because of scaled HP in LFE
		char szClassname[32];
		GetEntityClassname(inflictor, szClassname, sizeof(szClassname));
		if ((damagetype == 17) && ((StrEqual(szClassname, "prop_vehicle_airboat", false)) || (StrEqual(szClassname, "prop_vehicle_jeep", false))))
		{
			if ((damage > 50.0) && (damage < 200.0))
			{
				damage = 200.0;
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}

public void OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	CreateTimer(0.1, everyspawnpost, client, TIMER_FLAG_NO_MAPCHANGE);
	
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
				if (HasEntProp(i, Prop_Send, "m_bIsPlayerADev"))
				{
					if (GetEntProp(i, Prop_Send, "m_bIsPlayerADev"))
					{
						char SteamID[32];
						GetClientAuthId(i, AuthId_Steam2, SteamID, sizeof(SteamID));
						LogMessage("%N IsPlayerADev %s", i, SteamID);
					}
					SetEntProp(i, Prop_Send, "m_bIsPlayerADev", 0);
				}
				if (HasEntProp(i, Prop_Send, "m_bIsPlayerNicknine"))
				{
					if (GetEntProp(i, Prop_Send, "m_bIsPlayerNicknine"))
					{
						char SteamID[32];
						GetClientAuthId(i, AuthId_Steam2, SteamID, sizeof(SteamID));
						LogMessage("%N IsPlayerNicknine %s", i, SteamID);
					}
					SetEntProp(i, Prop_Send, "m_bIsPlayerNicknine", 0);
				}
			}
		}
	}
}

public Action everyspawnpost(Handle timer, int client)
{
	if (IsValidEntity(client))
	{
		if (HasEntProp(client, Prop_Send, "m_bIsPlayerADev")) SetEntProp(client, Prop_Send, "m_bIsPlayerADev", 0);
		if (HasEntProp(client, Prop_Send, "m_bIsPlayerNicknine")) SetEntProp(client, Prop_Send, "m_bIsPlayerNicknine", 0);
	}
	else CreateTimer(0.1, everyspawnpost, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action LFECreateVehicle(int client, int args)
{
	if (LastCmdRestrict[client] > GetTickedTime())
	{
		PrintToChat(client, "You cannot use this for another %1.1f seconds...", LastCmdRestrict[client]-GetTickedTime());
		return Plugin_Handled;
	}
	LastCmdRestrict[client] = GetTickedTime()+3.0;
	return Plugin_Continue;
}