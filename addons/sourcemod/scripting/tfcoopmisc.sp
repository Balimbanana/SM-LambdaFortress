#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude <SteamWorks>
#tryinclude <updater>
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#define PLUGIN_VERSION "1.09"
#define UPDATE_URL "https://raw.githubusercontent.com/Balimbanana/SM-LambdaFortress/master/addons/sourcemod/lfmiscfixesupdater.txt"

#pragma semicolon 1;
#pragma newdecls required;

ConVar sv_vote_issue_kick_allowed, sv_vote_issue_ban_allowed;
ConVar sv_cheats;
ConVar sv_class_cooldown, g_CVarRespawnItemCrate;
float LastCmdRestrict[128];
float flLastClassChange[128];
float flRemoveEntity[2048];
float g_flNoRecreate = 0.0;

float vecOriginalItemPosition[2048][3];
float vecOriginalItemAngles[2048][3];

enum
{
	CLASS_NONE = 0,
	CLASS_SCOUT = 1,
	CLASS_SNIPER = 2,
	CLASS_SOLDIER = 3,
	CLASS_DEMOMAN = 4,
	CLASS_MEDIC = 5,
	CLASS_HEAVY = 6,
	CLASS_PYRO = 7,
	CLASS_SPY = 8,
	CLASS_ENGINEER = 9,
	CLASS_CITIZEN = 10,
	CLASS_COMBINE = 11,
	MAX_CLASSES = CLASS_COMBINE
};

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
	RegConsoleCmd("bot", blckserver);
	RegConsoleCmd("bot_add", blckserver);
	RegConsoleCmd("bot_add_tf", blckserver);
	RegConsoleCmd("bot_forcefireweapon", blckserver);
	RegConsoleCmd("bot_forceattack2", blckserver);
	RegConsoleCmd("bot_forceattackon", blckserver);
	RegConsoleCmd("bot_flipout", blckserver);
	RegConsoleCmd("bot_defend", blckserver);
	RegConsoleCmd("bot_changeclass", blckserver);
	RegConsoleCmd("bot_selectweaponslot", blckserver);
	RegConsoleCmd("bot_dontmove", blckserver);
	RegConsoleCmd("bot_randomnames", blckserver);
	RegConsoleCmd("bot_saveme", blckserver);
	RegConsoleCmd("bot_jump", blckserver);
	RegConsoleCmd("bot_mimic", blckserver);
	RegConsoleCmd("bot_command", blckserver);
	RegConsoleCmd("bot_mimic_yaw_offset", blckserver);
	RegConsoleCmd("bot_kill", blckserver);
	RegConsoleCmd("bot_kick", blckserver);
	RegConsoleCmd("bot_changeteams", blckserver);
	RegConsoleCmd("bot_teleport", blckserver);
	RegConsoleCmd("bot_refill", blckserver);
	RegConsoleCmd("bot_warp_team_to_me", blckserver);
	RegConsoleCmd("bot_whack", blckserver);
	RegConsoleCmd("kickall", blckserver);
	RegConsoleCmd("kick", blckserver);
	RegConsoleCmd("kickid", blckserver);
	
	// Prevent spam of create/remove vehicle
	RegConsoleCmd("lfe_createvehicle", LFECreateVehicle);
	// Prevent certain taunts
	RegConsoleCmd("taunt_by_name", blocktaunt);
	RegConsoleCmd("taunt", killtaunt);
	// Fix CVars to actually apply correctly
	RegConsoleCmd("callvote", Command_CallVoteBlock);
	RegConsoleCmd("join_class", Command_JoinClass);
	RegConsoleCmd("joinclass", Command_JoinClass);
	
	HookEventEx("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	if (!HookEventEx("player_connect_client", EventHookPlayerConnect, EventHookMode_Pre))
	{
		HookEventEx("player_connect", EventHookPlayerConnect, EventHookMode_Pre);
	}
	HookEventEx("player_hurt", OnPlayerHurt, EventHookMode_Pre);
	HookEventEx("npc_hurt", OnNPCHurt, EventHookMode_Pre);
	HookEventEx("teamplay_round_win", OnRoundEnd, EventHookMode_Pre);
	/*
	HookEventEx("teamplay_round_stalemate", OnRoundEnd, EventHookMode_Pre);
	HookEventEx("teamplay_game_over", OnRoundEnd, EventHookMode_Pre);
	HookEventEx("teamplay_win_panel", OnRoundEnd, EventHookMode_Pre);
	HookEventEx("arena_win_panel", OnRoundEnd, EventHookMode_Pre);
	HookEventEx("pve_win_panel", OnRoundEnd, EventHookMode_Pre);
	*/
	HookEventEx("teamplay_round_start", OnRoundReset, EventHookMode_Post);
	HookEventEx("arena_round_start", OnRoundReset, EventHookMode_Post);
	HookEventEx("npc_death", OnNPCDeath, EventHookMode_Pre);
	HookEventEx("player_death", OnPlayerDeath, EventHookMode_Pre);
	RegServerCmd("createbot", createbot);
	CreateTimer(0.1, resetdev, _, TIMER_REPEAT);
	CreateTimer(1.0, RemovalEntities, _, TIMER_REPEAT);
	
	sv_vote_issue_kick_allowed = FindConVar("sv_vote_issue_kick_allowed");
	sv_vote_issue_ban_allowed = FindConVar("sv_vote_issue_ban_allowed");
	if (sv_vote_issue_ban_allowed == INVALID_HANDLE) sv_vote_issue_ban_allowed = CreateConVar("sv_vote_issue_ban_allowed", "0", "Enable voting to ban other players.", _, true, 0.0, true, 1.0);
	sv_cheats = FindConVar("sv_cheats");
	
	sv_class_cooldown = CreateConVar("sv_class_cooldown", "3.0", "Prevents changing classes too fast by this CVar amount.", _, true, 0.0, false);
	g_CVarRespawnItemCrate = CreateConVar("sv_itemcrate_respawntime", "0.0", "Respawns item_item_crate after this many seconds, set to 0 to disable.", _, true, 0.0);
	
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
		iEntity = -1;
		while ((iEntity = FindEntityByClassname(iEntity, "prop_vehicle_jeep")) != INVALID_ENT_REFERENCE)
		{
			if (IsValidEntity(iEntity))
			{
				SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnJeepTakeDamage);
			}
		}
	}
}

public void OnMapStart()
{
	//HookEntityOutput("logic_auto", "OnMapSpawn", OnMapSpawn);
	for (int i = MaxClients+1; i < 2048; i++)
	{
		vecOriginalItemPosition[i][0] = -1.0;
	}
	
	if (GetMapHistorySize() > -1)
	{
		int iEnt = -1;
		while ((iEnt = FindEntityByClassname(iEnt, "item_item_crate")) != INVALID_ENT_REFERENCE)
		{
			if (IsValidEntity(iEnt))
			{
				if (HasEntProp(iEnt, Prop_Data, "m_vecAbsOrigin"))
				{
					GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecOriginalItemPosition[iEnt]);
				}
				if (HasEntProp(iEnt, Prop_Data, "m_angRotation"))
				{
					GetEntPropVector(iEnt, Prop_Data, "m_angRotation", vecOriginalItemAngles[iEnt]);
				}
			}
		}
	}
}

public Action OnMapSpawn(const char[] output, int caller, int activator, float delay)
{
	
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

public bool OnClientConnect(int client, char[] rejectmsg, int maxlen)
{
	ClientCommand(client, "alias bot \"echo \"\"");
	ClientCommand(client, "alias bot_add \"echo \"\"");
	ClientCommand(client, "alias bot_add_tf \"echo \"\"");
	ClientCommand(client, "alias bot_kick \"echo \"\"");
	ClientCommand(client, "alias sv_shutdown \"echo nope\"");
	ClientCommand(client, "alias \"alias sv_shutdown nope\"");
	QueryClientConVar(client, "sv_cheats", clcheat, 0);
	
	return true;
}

public void clcheat(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any value)
{
	if (sv_cheats.IntValue == 0)
	{
		if (StringToInt(cvarValue) > 0)
		{
			SendConVarValue(client, sv_cheats, "0");
		}
	}
}

public Action blckserver(int client, int args)
{
	if (client == 0) return Plugin_Continue;
	return Plugin_Handled;
}

// Fix CVar sv_vote_issue_kick_allowed to actually block the vote if disabled
public Action Command_CallVoteBlock(int client, int args)
{
	if (args > 0)
	{
		static char szArg[1024];
		GetCmdArg(1, szArg, sizeof(szArg));
		if (StrEqual(szArg, "kick", false))
		{
			if (sv_vote_issue_kick_allowed != INVALID_HANDLE)
			{
				if (!sv_vote_issue_kick_allowed.IntValue)
				{
					return Plugin_Handled;
				}
			}
		}
		else if (StrEqual(szArg, "ban", false))
		{
			if (sv_vote_issue_ban_allowed != INVALID_HANDLE)
			{
				if (!sv_vote_issue_ban_allowed.IntValue)
				{
					return Plugin_Handled;
				}
			}
		}
		GetCmdArgString(szArg, sizeof(szArg));
		if ((StrContains(szArg, "sv_", false) != -1) || (StrContains(szArg, ";", false) != -1))
		{
			PrintToServer("%N attempted to use escape character using: '%s'", client, szArg);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action Command_JoinClass(int client, int args)
{
	if ((!IsValidEntity(client)) || (client == 0)) return Plugin_Continue;
	if (flLastClassChange[client] < GetTickedTime())
	{
		flLastClassChange[client] = GetTickedTime() + sv_class_cooldown.FloatValue;
	}
	else
	{
		PrintToChat(client, "You cannot change classes for another %1.1f seconds!", flLastClassChange[client] - GetTickedTime());
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	bool bKicked = false;
	if (IsClientConnected(client))
	{
		if (IsClientInGame(client))
		{
			if (IsFakeClient(client))
			{
				if (!sv_cheats.BoolValue)
				{
					KickClient(client, "");
					bKicked = true;
				}
			}
		}
	}
	if (!bKicked) CreateTimer(5.0, ApplyHooks, client, TIMER_FLAG_NO_MAPCHANGE);
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
	
	if (IsValidEntity(inflictor))
	{
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
	else if (StrEqual(szClassname, "prop_vehicle_jeep", false))
	{
		SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnJeepTakeDamage);
	}
	else if (StrEqual(szClassname, "tf_projectile_energy_ring", false))
	{
		flRemoveEntity[iEntity] = GetGameTime() + 4.0;
	}
	else if (StrEqual(szClassname, "tf_projectile_healing_bolt", false))
	{
		SDKHookEx(iEntity, SDKHook_Touch, HealingBoltStartTouch);
	}
	
	return;
}

public void OnEntityDestroyed(int iEntity)
{
	if ((iEntity > 0) && (iEntity <= 2048))
	{
		flRemoveEntity[iEntity] = 0.0;
		if ((IsValidEntity(iEntity)) && (g_flNoRecreate < GetTickedTime()))
		{
			char szClassname[32];
			GetEntityClassname(iEntity, szClassname, sizeof(szClassname));
			if ((StrEqual(szClassname, "item_teamflag", false)) && (HasEntProp(iEntity, Prop_Data, "m_iTeamNum")))
			{
				if (HasEntProp(iEntity, Prop_Data, "m_hParent"))
				{
					int hParent = GetEntPropEnt(iEntity, Prop_Data, "m_hParent");
					if (IsValidEntity(hParent))
					{
						float vecOrigin[3];
						GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", vecOrigin);
						int iFlagTeam = GetEntProp(iEntity, Prop_Data, "m_iTeamNum");
						int iEnt = -1;
						while ((iEnt = FindEntityByClassname(iEnt, "func_capturezone")) != INVALID_ENT_REFERENCE)
						{
							if (IsValidEntity(iEnt))
							{
								if (HasEntProp(iEnt, Prop_Data, "m_iTeamNum"))
								{
									if (GetEntProp(iEnt, Prop_Data, "m_iTeamNum") == iFlagTeam)
									{
										GetEntPropVector(iEnt, Prop_Data, "m_vecAbsOrigin", vecOrigin);
										vecOrigin[2] += 10.0;
										break;
									}
								}
							}
						}
						
						int iRecreate = CreateEntityByName("item_teamflag");
						if (IsValidEntity(iRecreate))
						{
							char szStat[64];
							Format(szStat, sizeof(szStat), "%f", GetEntPropFloat(iEntity, Prop_Send, "m_flResetTime"));
							DispatchKeyValue(iRecreate, "ReturnTime", szStat);
							Format(szStat, sizeof(szStat), "%i", GetEntProp(iEntity, Prop_Data, "m_nGameType"));
							DispatchKeyValue(iRecreate, "GameType", szStat);
							GetEntPropString(iEntity, Prop_Data, "m_szModel", szStat, sizeof(szStat));
							DispatchKeyValue(iRecreate, "flag_model", szStat);
							GetEntPropString(iEntity, Prop_Data, "m_szHudIcon", szStat, sizeof(szStat));
							DispatchKeyValue(iRecreate, "flag_icon", szStat);
							GetEntPropString(iEntity, Prop_Data, "m_szPaperEffect", szStat, sizeof(szStat));
							DispatchKeyValue(iRecreate, "flag_paper", szStat);
							GetEntPropString(iEntity, Prop_Data, "m_szTrailEffect", szStat, sizeof(szStat));
							DispatchKeyValue(iRecreate, "flag_trail", szStat);
							Format(szStat, sizeof(szStat), "%i", GetEntProp(iEntity, Prop_Data, "m_nUseTrailEffect"));
							DispatchKeyValue(iRecreate, "trail_effect", szStat);
							Format(szStat, sizeof(szStat), "%i", GetEntProp(iEntity, Prop_Data, "m_bVisibleWhenDisabled"));
							DispatchKeyValue(iRecreate, "VisibleWhenDisabled", szStat);
							Format(szStat, sizeof(szStat), "%i", GetEntProp(iEntity, Prop_Data, "m_iTeamNum"));
							DispatchKeyValue(iRecreate, "TeamNum", szStat);
							Format(szStat, sizeof(szStat), "%i", GetEntProp(iEntity, Prop_Data, "m_fEffects"));
							DispatchKeyValue(iRecreate, "effects", szStat);
							
							TeleportEntity(iRecreate, vecOrigin, NULL_VECTOR, NULL_VECTOR);
							
							DispatchSpawn(iRecreate);
							ActivateEntity(iRecreate);
						}
					}
				}
			}
			else if ((StrEqual(szClassname, "item_item_crate", false)) && (g_CVarRespawnItemCrate.FloatValue > 0.0))
			{
				if (vecOriginalItemPosition[iEntity][0] != -1.0)
				{
					char szStat[128];
					Handle dp = CreateDataPack();
					CreateDataTimer(g_CVarRespawnItemCrate.FloatValue, RespawnItemCrates, dp, TIMER_FLAG_NO_MAPCHANGE);
					WritePackCell(dp, iEntity);
					WritePackCell(dp, GetEntProp(iEntity, Prop_Data, "m_CrateType"));
					WritePackCell(dp, GetEntProp(iEntity, Prop_Data, "m_nItemCount"));
					WritePackCell(dp, GetEntProp(iEntity, Prop_Data, "m_CrateAppearance"));
					WritePackCell(dp, GetEntProp(iEntity, Prop_Data, "m_nSkin"));
					WritePackCell(dp, GetEntProp(iEntity, Prop_Data, "m_nBody"));
					GetEntPropString(iEntity, Prop_Data, "m_strItemClass", szStat, sizeof(szStat));
					WritePackString(dp, szStat);
					GetEntPropString(iEntity, Prop_Data, "m_strAlternateMaster", szStat, sizeof(szStat));
					WritePackString(dp, szStat);
				}
			}
		}
	}
}

public Action RespawnItemCrates(Handle timer, Handle dp)
{
	if (dp != INVALID_HANDLE)
	{
		ResetPack(dp);
		int iIndex = ReadPackCell(dp);
		if (vecOriginalItemPosition[iIndex][0] != -1.0)
		{
			int iRecreate = CreateEntityByName("item_item_crate");
			if (IsValidEntity(iRecreate))
			{
				char szStat[128];
				Format(szStat, sizeof(szStat), "%i", ReadPackCell(dp));
				DispatchKeyValue(iRecreate, "CrateType", szStat);
				Format(szStat, sizeof(szStat), "%i", ReadPackCell(dp));
				DispatchKeyValue(iRecreate, "ItemCount", szStat);
				Format(szStat, sizeof(szStat), "%i", ReadPackCell(dp));
				DispatchKeyValue(iRecreate, "CrateAppearance", szStat);
				Format(szStat, sizeof(szStat), "%i", ReadPackCell(dp));
				DispatchKeyValue(iRecreate, "Skin", szStat);
				Format(szStat, sizeof(szStat), "%i", ReadPackCell(dp));
				DispatchKeyValue(iRecreate, "Body", szStat);
				ReadPackString(dp, szStat, sizeof(szStat));
				DispatchKeyValue(iRecreate, "ItemClass", szStat);
				ReadPackString(dp, szStat, sizeof(szStat));
				DispatchKeyValue(iRecreate, "SpecificResupply", szStat);
				
				TeleportEntity(iRecreate, vecOriginalItemPosition[iIndex], vecOriginalItemAngles[iIndex], NULL_VECTOR);
				// Make new index
				float vecCopy[3];
				vecCopy[0] = vecOriginalItemPosition[iIndex][0];
				vecCopy[1] = vecOriginalItemPosition[iIndex][1];
				vecCopy[2] = vecOriginalItemPosition[iIndex][2];
				vecOriginalItemPosition[iIndex][0] = -1.0;
				vecOriginalItemPosition[iRecreate] = vecCopy;
				
				DispatchSpawn(iRecreate);
				ActivateEntity(iRecreate);
			}
		}
	}
}

public Action HealingBoltStartTouch(int iEntity, int iOther)
{
	if (IsValidEntity(iOther))
	{
		AcceptEntityInput(iEntity, "kill");
		// Heals 75
		if (HasEntProp(iOther, Prop_Send, "m_iMaxHealth"))
		{
			int iMaxHealth = GetEntProp(iOther, Prop_Send, "m_iMaxHealth");
			int iHealth = GetEntProp(iOther, Prop_Data, "m_iHealth");
			if (iHealth + 75 > iMaxHealth) SetEntProp(iOther, Prop_Data, "m_iHealth", iMaxHealth);
			else SetEntProp(iOther, Prop_Data, "m_iHealth", iHealth + 75);
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
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

public Action EventHookPlayerConnect(Handle event, const char[] name, bool dontBroadcast)
{
	char szNetworkID[64];
	GetEventString(event, "networkid", szNetworkID, sizeof(szNetworkID));
	if (StrEqual(szNetworkID, "BOT", false))
	{
		if (sv_cheats.IntValue == 0)
		{
			return Plugin_Handled;
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

bool bHandledNextFirePly = false;
bool bHandledNextFire = false;

public Action OnPlayerHurt(Handle event, const char[] name, bool dontBroadcast)
{
	int attacker = GetEventInt(event, "attacker_index");
	int health = GetEventInt(event, "health");
	if ((IsValidEntity(attacker)) && (health == 0))
	{
		if ((attacker > 0) && (attacker < MaxClients+1))
		{
			int iTeamNum = GetEntProp(attacker, Prop_Send, "m_iTeamNum");
			if (iTeamNum == 3)
			{
				if (GetEntPropEnt(attacker, Prop_Data, "m_hVehicle") != -1) return Plugin_Continue;
				
				Handle player_death = CreateEvent("player_death");
				if (player_death != INVALID_HANDLE)
				{
					int victim = GetEventInt(event, "victim_index");
					SetEventInt(player_death, "userid", GetClientUserId(attacker));
					int m_Item = 0;
					int iWeapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
					if (IsValidEntity(iWeapon))
					{
						if (HasEntProp(iWeapon, Prop_Send, "m_Item")) m_Item = GetEntProp(iWeapon, Prop_Send, "m_Item");
					}
					SetEventInt(player_death, "weapon_def_index", m_Item);
					
					SetEventInt(player_death, "victim_entindex", victim);
					SetEventInt(player_death, "attacker", attacker);
					
					SetEventInt(player_death, "inflictor_entindex", iWeapon);
					char szWeapon[64];
					GetClientWeapon(attacker, szWeapon, sizeof(szWeapon));
					ReplaceStringEx(szWeapon, sizeof(szWeapon), "tf_weapon_", "", -1, -1, false);
					if ((StrContains(szWeapon, "pistol", false) != -1) || (StrContains(szWeapon, "handgun", false) != -1)) Format(szWeapon, sizeof(szWeapon), "pistol");
					else if (StrEqual(szWeapon, "pep_brawler_blaster", false)) Format(szWeapon, sizeof(szWeapon), "pep_brawlerblaster");
					SetEventString(player_death, "weapon", szWeapon);
					SetEventInt(player_death, "weaponid", GetEventInt(event, "weaponid"));
					SetEventInt(player_death, "damagebits", DMG_BULLET);
					SetEventInt(player_death, "customkill", 0);
					SetEventString(player_death, "weapon_logclassname", szWeapon);
					//Also has minicrit allseecrit
					SetEventInt(player_death, "crit_type", GetEventInt(event, "crit"));
					SetEventInt(player_death, "victim_index", victim);
					SetEventInt(player_death, "attacker_index", attacker);
					SetEventString(player_death, "attacker_name", "player");
					SetEventInt(player_death, "attacker_team", iTeamNum);
					
					// TODO: Assisters
					SetEventInt(player_death, "assister_index", -1);
					//SetEventString(player_death, "assister_name", "player");
					//SetEventInt(player_death, "assister_team", //GetTeam
					SetEventInt(player_death, "assister", -1);
					
					FireEvent(player_death, false);
					
					bHandledNextFirePly = true;
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action OnNPCHurt(Handle event, const char[] name, bool dontBroadcast)
{
	int attacker = GetEventInt(event, "attacker_index");
	int health = GetEventInt(event, "health");
	
	if ((IsValidEntity(attacker)) && (health == 0))
	{
		if ((attacker > 0) && (attacker < MaxClients+1))
		{
			int iTeamNum = GetEntProp(attacker, Prop_Send, "m_iTeamNum");
			if (iTeamNum == 3)
			{
				if (GetEntPropEnt(attacker, Prop_Data, "m_hVehicle") != -1) return Plugin_Continue;
				
				Handle npc_death = CreateEvent("npc_death");
				if (npc_death != INVALID_HANDLE)
				{
					char szName[64];
					char szClass[64];
					int victim = GetEventInt(event, "victim_index");
					SetEventInt(npc_death, "victim_index", victim);
					GetEntityClassname(victim, szClass, sizeof(szClass));
					SetEventString(npc_death, "victim_name", szClass);
					GetEntPropString(victim, Prop_Data, "m_iName", szName, sizeof(szName));
					SetEventString(npc_death, "victim_entname", szName);
					SetEventInt(npc_death, "victim_team", GetEntProp(victim, Prop_Send, "m_iTeamNum"));
					SetEventInt(npc_death, "attacker_index", attacker);
					SetEventString(npc_death, "attacker_name", "player");
					SetEventInt(npc_death, "attacker_team", iTeamNum);
					
					char szWeapon[64];
					GetClientWeapon(attacker, szWeapon, sizeof(szWeapon));
					ReplaceStringEx(szWeapon, sizeof(szWeapon), "tf_weapon_", "", -1, -1, false);
					if ((StrContains(szWeapon, "pistol", false) != -1) || (StrContains(szWeapon, "handgun", false) != -1)) Format(szWeapon, sizeof(szWeapon), "pistol");
					else if (StrEqual(szWeapon, "pep_brawler_blaster", false)) Format(szWeapon, sizeof(szWeapon), "pep_brawlerblaster");
					SetEventString(npc_death, "weapon", szWeapon);
					SetEventInt(npc_death, "weaponid", GetEventInt(event, "weaponid"));
					SetEventString(npc_death, "weapon_logclassname", szWeapon);
					SetEventInt(npc_death, "damagebits", DMG_BULLET);
					SetEventInt(npc_death, "customkill", 0);
					
					// TODO: Assister
					SetEventInt(npc_death, "assister_index", -1);
					SetEventString(npc_death, "assister_name", "");
					SetEventInt(npc_death, "assister_team", 0);
					FireEvent(npc_death, false);
					
					bHandledNextFire = true;
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action OnNPCDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if (bHandledNextFire && (GetEventInt(event, "attacker_team") == 3) && (GetEventInt(event, "attacker_index") == 0))
	{
		bHandledNextFire = false;
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action createbot(int args)
{
	int iBot = CreateFakeClient("Bot01");
	if (IsValidEntity(iBot))
	{
		DispatchSpawn(iBot);
		ActivateEntity(iBot);
		SetEntProp(iBot, Prop_Send, "m_iClass", GetRandomInt(0, 9));
	}
	return Plugin_Handled;
}

public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if (bHandledNextFirePly && (GetEventInt(event, "attacker_team") == 3) && (GetEventInt(event, "inflictor_entindex") == 0))
	{
		bHandledNextFirePly = false;
		return Plugin_Handled;
	}
	
	char szAttackerName[128];
	GetEventString(event, "attacker_name", szAttackerName, sizeof(szAttackerName));
	if (StrEqual(szAttackerName, "npc_rocket_turret", false))
	{
		SetEventString(event, "attacker_name", "Portal Rocket Turret");
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public Action OnJeepTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if (IsValidEntity(attacker))
	{
		if (HasEntProp(victim, Prop_Data, "m_hPlayer"))
		{
			int hPlayer = GetEntPropEnt(victim, Prop_Data, "m_hPlayer");
			if ((IsValidEntity(hPlayer)) && (hPlayer > 0) && (hPlayer <= MaxClients))
			{
				if ((HasEntProp(attacker, Prop_Data, "m_iTeamNum")) && (HasEntProp(hPlayer, Prop_Data, "m_iTeamNum")))
				{
					int iPlayerTeam = GetEntProp(hPlayer, Prop_Data, "m_iTeamNum");
					if (GetEntProp(attacker, Prop_Data, "m_iTeamNum") == iPlayerTeam)
					{
						return Plugin_Continue;
					}
					if (IsValidEntity(inflictor))
					{
						if (HasEntProp(inflictor, Prop_Data, "m_iTeamNum"))
						{
							if (GetEntProp(inflictor, Prop_Data, "m_iTeamNum") == iPlayerTeam)
							{
								return Plugin_Continue;
							}
						}
					}
				}
				float vecOrigin[3];
				if (HasEntProp(attacker, Prop_Data, "m_vecAbsOrigin"))
				{
					GetEntPropVector(attacker, Prop_Data, "m_vecAbsOrigin", vecOrigin);
				}
				SetEntProp(hPlayer, Prop_Data, "m_iHealth", GetEntProp(hPlayer, Prop_Data, "m_iHealth") - RoundFloat(damage/1.3));
				if (GetEntProp(hPlayer, Prop_Data, "m_iHealth") <= 0)
				{
					AcceptEntityInput(victim, "ExitVehicleImmediate");
					//SetEntPropEnt(hPlayer, Prop_Data, "m_hVehicle", -1);
					//SetEntPropEnt(victim, Prop_Data, "m_hPlayer", -1);
					SDKHooks_TakeDamage(hPlayer, attacker, inflictor, damage, damagetype, -1, NULL_VECTOR, vecOrigin);
					FireEntityOutput(victim, "PlayerOff", -1, 0.0);
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public Action OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	g_flNoRecreate = GetTickedTime() + 30.0;
	return Plugin_Continue;
}

public Action OnRoundReset(Handle event, const char[] name, bool dontBroadcast)
{
	int iEntity = CreateEntityByName("ai_relationship");
	if (IsValidEntity(iEntity))
	{
		DispatchKeyValue(iEntity, "target", "npc_alyx");
		DispatchKeyValue(iEntity, "subject", "tf_zombie");
		DispatchKeyValue(iEntity, "disposition", "3");
		DispatchKeyValue(iEntity, "rank", "999");
		DispatchKeyValue(iEntity, "reciprocal", "1");
		DispatchKeyValue(iEntity, "StartActive", "1");
		
		DispatchSpawn(iEntity);
		ActivateEntity(iEntity);
	}
	iEntity = CreateEntityByName("ai_relationship");
	if (IsValidEntity(iEntity))
	{
		DispatchKeyValue(iEntity, "target", "npc_alyx");
		DispatchKeyValue(iEntity, "subject", "bot_npc_archer");
		DispatchKeyValue(iEntity, "disposition", "3");
		DispatchKeyValue(iEntity, "rank", "999");
		DispatchKeyValue(iEntity, "reciprocal", "1");
		DispatchKeyValue(iEntity, "StartActive", "1");
		
		DispatchSpawn(iEntity);
		ActivateEntity(iEntity);
	}
	
	return Plugin_Continue;
}

public void OnMapEnd()
{
	
}

public Action RemovalEntities(Handle timer)
{
	float flTime = GetGameTime();
	for (int i = MaxClients+1; i < 2048; i++)
	{
		if (IsValidEntity(i))
		{
			if (flRemoveEntity[i] > 0.0)
			{
				if (flRemoveEntity[i] < flTime)
				{
					AcceptEntityInput(i, "kill");
					flRemoveEntity[i] = 0.0;
				}
			}
		}
	}
}

public Action resetdev(Handle timer)
{
	for (int i = 1;i<MaxClients+1;i++)
	{
		if (IsValidEntity(i))
		{
			if (IsClientInGame(i))
			{
				QueryClientConVar(i, "sv_cheats", clcheat, 0);
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
				if (HasEntProp(i, Prop_Send, "m_flHypeMeter"))
				{
					if (GetEntPropFloat(i, Prop_Send, "m_flHypeMeter") < 0.0)
					{
						SetEntPropFloat(i, Prop_Send, "m_flHypeMeter", 0.0);
					}
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

public Action killtaunt(int client, int args)
{
	if ((IsValidEntity(client)) && (client > 0))
	{
		if (HasEntProp(client, Prop_Send, "m_iClass"))
		{
			int iClass = GetEntProp(client, Prop_Send, "m_iClass");
			if (iClass == CLASS_MEDIC)
			{
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public Action blocktaunt(int client, int args)
{
	if (args > 0)
	{
		if (IsValidEntity(client))
		{
			if (HasEntProp(client, Prop_Data, "m_hActiveWeapon"))
			{
				int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
				if (IsValidEntity(iWeapon))
				{
					if (HasEntProp(iWeapon, Prop_Send, "m_Item"))
					{
						// UberSaw exploit
						if (GetEntProp(iWeapon, Prop_Send, "m_Item") == 37)
						{
							return Plugin_Handled;
						}
					}
				}
			}
		}
		static char szArg[32];
		GetCmdArg(1, szArg, sizeof(szArg));
		if ((StringToInt(szArg) < 1) && (!StrEqual(szArg, "default", false))) return Plugin_Handled;
		
		return Plugin_Continue;
	}
	return Plugin_Handled;
}