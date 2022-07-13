#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude <SteamWorks>
#tryinclude <updater>
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#pragma semicolon 1;
#pragma newdecls required;
#pragma dynamic 2097152;

#define PLUGIN_VERSION "0.2"
#define UPDATE_URL "https://raw.githubusercontent.com/Balimbanana/SM-LambdaFortress/master/addons/sourcemod/lfportalfixupdater.txt"

int WeapList = -1;
char szMap[64];
bool bMapStarted = false;
bool bLoadedAfterMap = false;
bool HasPickedUpPortal2 = false;
float flSoundChecksSkip = 0.0;

float LastVel[128][3];
float LastApplyVel[128];
float EntryAng[128];
float flShootPlyDelay[128];
Handle dpClient[128];
int LastPortal[128];

public Plugin myinfo = 
{
	name = "LFE Portal Utils",
	author = "Balim",
	description = "LFE Portal fixes and utils",
	version = PLUGIN_VERSION,
	url = "https://github.com/Balimbanana/SM-LambdaFortress"
}

public void OnPluginStart()
{
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	HookEventEx("entity_killed", Event_EntityKilled, EventHookMode_Post);
	HookEventEx("teamplay_round_start", OnRoundReset, EventHookMode_Post);
	HookEventEx("arena_round_start", OnRoundReset, EventHookMode_Post);
	
	RegConsoleCmd("dropweapon", DropPortalGun);
	
	RegServerCmd("changelevel", ChangeLevelTriggers);
	
	if (bLoadedAfterMap)
	{
		int ent = -1;
		while((ent = FindEntityByClassname(ent, "prop_physics")) != INVALID_ENT_REFERENCE)
		{
			if (IsValidEntity(ent))
			{
				SetupPortalBox(ent);
			}
		}
		
		ent = -1;
		while((ent = FindEntityByClassname(ent, "tf_weapon_portalgun")) != INVALID_ENT_REFERENCE)
		{
			if (IsValidEntity(ent))
			{
				SDKHookEx(ent, SDKHook_StartTouch, StartTouchPortalGun);
				HookSingleEntityOutput(ent, "OnPlayerUse", TouchPortalGunOutput);
				HookSingleEntityOutput(ent, "OnPlayerPickup", TouchPortalGunOutput);
			}
		}
		
		bLoadedAfterMap = false;
	}
	
	AddNormalSoundHook(SoundFixesNormal);
}

public Action ChangeLevelTriggers(int args)
{
	flSoundChecksSkip = GetTickedTime()+1.0;
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name,"updater",false))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnClientDisconnect(int client)
{
	LastApplyVel[client] = 0.0;
	LastVel[client] = NULL_VECTOR;
	LastPortal[client] = -1;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if ((late) && (GetMapHistorySize() != -1))
	{
		bLoadedAfterMap = true;
	}
}

public void OnMapStart()
{
	if (GetMapHistorySize() != -1)
	{
		HookEntityOutput("prop_portal", "OnPlacedSuccessfully", PortalPlaced);
		GetCurrentMap(szMap, sizeof(szMap));
		if ((StrContains(szMap, "escape_", false) == 0) || (StrContains(szMap, "testchmb_a_", false) == 0))
		{
			CreateTimer(1.0, TimerCheckPortalPos, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		bMapStarted = true;
		
		if (FileExists("sound/vo/aperture_ai/generic_security_camera_destroyed-1.wav", true, NULL_STRING)) PrecacheSound("vo/aperture_ai/generic_security_camera_destroyed-1.wav", true);
		if (FileExists("sound/vo/aperture_ai/generic_security_camera_destroyed-2.wav", true, NULL_STRING)) PrecacheSound("vo/aperture_ai/generic_security_camera_destroyed-2.wav", true);
		if (FileExists("sound/vo/aperture_ai/generic_security_camera_destroyed-3.wav", true, NULL_STRING)) PrecacheSound("vo/aperture_ai/generic_security_camera_destroyed-3.wav", true);
		if (FileExists("sound/vo/aperture_ai/generic_security_camera_destroyed-4.wav", true, NULL_STRING)) PrecacheSound("vo/aperture_ai/generic_security_camera_destroyed-4.wav", true);
		if (FileExists("sound/vo/aperture_ai/generic_security_camera_destroyed-5.wav", true, NULL_STRING)) PrecacheSound("vo/aperture_ai/generic_security_camera_destroyed-5.wav", true);
		if (FileExists("sound/player/futureshoes1.wav", true, NULL_STRING)) PrecacheSound("sound/player/futureshoes1.wav", true);
		if (FileExists("sound/player/futureshoes2.wav", true, NULL_STRING)) PrecacheSound("sound/player/futureshoes2.wav", true);
	}
}

public Action OnRoundReset(Handle event, const char[] name, bool dontBroadcast)
{
	int ent = -1;
	while((ent = FindEntityByClassname(ent, "prop_physics")) != INVALID_ENT_REFERENCE)
	{
		if (IsValidEntity(ent))
		{
			SetupPortalBox(ent);
		}
	}
	
	ent = -1;
	while((ent = FindEntityByClassname(ent, "tf_weapon_portalgun")) != INVALID_ENT_REFERENCE)
	{
		if (IsValidEntity(ent))
		{
			SDKHookEx(ent, SDKHook_StartTouch, StartTouchPortalGun);
			HookSingleEntityOutput(ent, "OnPlayerUse", TouchPortalGunOutput);
			HookSingleEntityOutput(ent, "OnPlayerPickup", TouchPortalGunOutput);
		}
	}
	
	return Plugin_Continue;
}

public Action block(int client, int args)
{
	return Plugin_Handled;
}

public Action OnLevelInit(const char[] mapName, char mapEntities[2097152])
{
	bMapStarted = false;
}

public void OnGameFrame()
{
	static float vecShootVelocity[3], vecCurPortalAngles[3], vecPortalOrigin[3], vecEndAdjustedVelocity[3];
	static float VelocityOffset[2];
	if (GetClientCount(false) > 0)
	{
		for (int i = 1; i < MaxClients+1; i++)
		{
			if (IsValidEntity(i))
			{
				if (IsClientConnected(i))
				{
					if (IsPlayerAlive(i))
					{
						if ((HasEntProp(i, Prop_Data, "m_hPortalEnvironment")) && (LastApplyVel[i] < GetGameTime()))
						{
							int hPortalEnvironment = GetEntPropEnt(i,Prop_Data,"m_hPortalEnvironment");
							if (hPortalEnvironment != -1)
							{
								if ((hPortalEnvironment != LastPortal[i]) && (LastPortal[i] != -1))
								{
									LastPortal[i] = -1;
									GetEntPropVector(hPortalEnvironment, Prop_Data, "m_vecAbsOrigin", vecPortalOrigin);
									GetEntPropVector(hPortalEnvironment, Prop_Data, "m_angRotation", vecCurPortalAngles);
									
									NegateVector(LastVel[i]);
									VelocityOffset[0] = LastVel[i][0]+LastVel[i][1];
									VelocityOffset[1] = LastVel[i][2];
									
									if (((EntryAng[i] > 10.0) || (EntryAng[i] < -10.0)) && (((vecCurPortalAngles[0] < 10.0) && (vecCurPortalAngles[0] > -10.0)) || ((vecCurPortalAngles[0] < -44.0) && (vecCurPortalAngles[0] > -90.0))))
									{
										//AngledApply
										VelocityOffset[0] = LastVel[i][2];
										VelocityOffset[1] = (LastVel[i][0]+LastVel[i][1])*1.5+(LastVel[i][2]);
									}
									
									vecEndAdjustedVelocity[0] = (vecPortalOrigin[0] + (VelocityOffset[0] * Cosine(DegToRad(vecCurPortalAngles[1]))));
									vecEndAdjustedVelocity[1] = (vecPortalOrigin[1] + (VelocityOffset[0] * Sine(DegToRad(vecCurPortalAngles[1]))));
									vecEndAdjustedVelocity[2] = (vecPortalOrigin[2] - (VelocityOffset[1] * Sine(DegToRad(vecCurPortalAngles[0]))));
									
									MakeVectorFromPoints(vecPortalOrigin, vecEndAdjustedVelocity, vecShootVelocity);
									ScaleVector(vecShootVelocity, 0.75);
									
									if (dpClient[i] != INVALID_HANDLE) CloseHandle(dpClient[i]);
									
									Handle dp = CreateDataPack();
									WritePackFloat(dp, vecShootVelocity[0]);
									WritePackFloat(dp, vecShootVelocity[1]);
									WritePackFloat(dp, vecShootVelocity[2]);
									flShootPlyDelay[i] = GetGameTime()+0.09;
									dpClient[i] = dp;
									
									LastApplyVel[i] = GetGameTime()+0.1;
								}
								else
								{
									LastPortal[i] = hPortalEnvironment;
									GetEntPropVector(i, Prop_Data, "m_vecAbsVelocity", LastVel[i]);
									GetEntPropVector(hPortalEnvironment, Prop_Data, "m_angRotation", vecCurPortalAngles);
									EntryAng[i] = vecCurPortalAngles[0];
								}
							}
							else LastPortal[i] = -1;
						}
						else if (flShootPlyDelay[i] != 0.0)
						{
							if (flShootPlyDelay[i] <= GetGameTime())
							{
								if (dpClient[i] != INVALID_HANDLE)
								{
									ResetPack(dpClient[i]);
									vecShootVelocity[0] = ReadPackFloat(dpClient[i]);
									vecShootVelocity[1] = ReadPackFloat(dpClient[i]);
									vecShootVelocity[2] = ReadPackFloat(dpClient[i]);
									CloseHandle(dpClient[i]);
									dpClient[i] = INVALID_HANDLE;
									
									flShootPlyDelay[i] = 0.0;
									TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, vecShootVelocity);
								}
							}
						}
					}
				}
			}
		}
	}
}

public Action TimerCheckPortalPos(Handle timer)
{
	int ent = -1;
	while((ent = FindEntityByClassname(ent, "prop_portal")) != INVALID_ENT_REFERENCE)
	{
		if (IsValidEntity(ent))
		{
			if (HasEntProp(ent, Prop_Data, "m_bActivated"))
			{
				if (GetEntProp(ent, Prop_Data, "m_bActivated"))
				{
					float vecOrigin[3];
					float vecCamOrigin[3];
					if (HasEntProp(ent, Prop_Data, "m_vecOrigin")) GetEntPropVector(ent, Prop_Data, "m_vecOrigin", vecOrigin);
					else if (HasEntProp(ent, Prop_Data, "m_vecAbsOrigin")) GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", vecOrigin);
					int cameraent = -1;
					while((cameraent = FindEntityByClassname(cameraent, "npc_security_camera")) != INVALID_ENT_REFERENCE)
					{
						if (IsValidEntity(cameraent))
						{
							if (HasEntProp(cameraent, Prop_Data, "m_bEnabled"))
							{
								if (GetEntProp(cameraent, Prop_Data, "m_bEnabled"))
								{
									if (HasEntProp(cameraent, Prop_Data, "m_vecAbsOrigin")) GetEntPropVector(cameraent, Prop_Data, "m_vecAbsOrigin", vecCamOrigin);
									else if (HasEntProp(cameraent, Prop_Data, "m_vecOrigin")) GetEntPropVector(cameraent, Prop_Data, "m_vecOrigin", vecCamOrigin);
									if (GetVectorDistance(vecOrigin, vecCamOrigin, false) < 50.0)
									{
										AcceptEntityInput(cameraent, "Ragdoll");
									}
								}
							}
						}
					}
				}
			}
		}
	}
	CreateTimer(0.5, TimerCheckPortalPos, _, TIMER_FLAG_NO_MAPCHANGE);
	
	return Plugin_Handled;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if ((StrEqual(classname, "prop_physics", false)) && (bMapStarted))
	{
		if (!SDKHookEx(entity,SDKHook_Spawn,SpawnPost)) CreateTimer(0.1, SpawnPostTimer, entity, TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (StrContains(classname,"tf_weapon_portalgun",false) != -1)
	{
		SDKHookEx(entity, SDKHook_StartTouch, StartTouchPortalGun);
		HookSingleEntityOutput(entity, "OnPlayerUse", TouchPortalGunOutput);
		HookSingleEntityOutput(entity, "OnPlayerPickup", TouchPortalGunOutput);
	}
	else if (StrEqual(classname,"item_battery",false))
	{
		if (!SDKHookEx(entity, SDKHook_Spawn, SpawnPostRemove)) CreateTimer(0.1, SpawnPostRemoveTimer, entity, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void SpawnPost(int entity)
{
	SDKUnhook(entity, SDKHook_Spawn, SpawnPost);
	SetupPortalBox(entity);
}

public void SpawnPostRemove(int entity)
{
	SDKUnhook(entity, SDKHook_Spawn, SpawnPost);
	AcceptEntityInput(entity,"kill");
}

public Action SpawnPostRemoveTimer(Handle timer, int entity)
{
	if ((IsValidEntity(entity)) && (entity > MaxClients)) AcceptEntityInput(entity, "kill");
}

public Action SpawnPostTimer(Handle timer, int entity)
{
	SetupPortalBox(entity);
}

void SetupPortalBox(int entity)
{
	if (IsValidEntity(entity))
	{
		if (HasEntProp(entity, Prop_Data, "m_ModelName"))
		{
			char szModel[64];
			GetEntPropString(entity, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
			if (StrEqual(szModel, "models/props/metal_box.mdl", false))
			{
				if (HasEntProp(entity, Prop_Data, "m_iszOverrideScript"))
				{
					char szOverrideScr[32];
					GetEntPropString(entity, Prop_Data, "m_iszOverrideScript", szOverrideScr, sizeof(szOverrideScr));
					if (StrContains(szOverrideScr, "mass", false) == -1)
					{
						float vecOrigin[3], vecAngles[3];
						char szSF[8], szSkin[4], szBody[4], szName[128];
						if (HasEntProp(entity, Prop_Data, "m_vecOrigin")) GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vecOrigin);
						else if (HasEntProp(entity, Prop_Data, "m_vecAbsOrigin")) GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vecOrigin);
						if (HasEntProp(entity, Prop_Data, "m_angAbsRotation")) GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", vecAngles);
						else if (HasEntProp(entity, Prop_Data, "m_angRotation")) GetEntPropVector(entity, Prop_Data, "m_angRotation", vecAngles);
						if (HasEntProp(entity, Prop_Data, "m_nSkin")) Format(szSkin, sizeof(szSkin), "%i", GetEntProp(entity, Prop_Data, "m_nSkin"));
						if (HasEntProp(entity, Prop_Data, "m_nBody")) Format(szBody, sizeof(szBody), "%i", GetEntProp(entity, Prop_Data, "m_nBody"));
						if (HasEntProp(entity, Prop_Data, "m_spawnflags")) Format(szSF, sizeof(szSF), "%i", GetEntProp(entity, Prop_Data, "m_spawnflags"));
						if (HasEntProp(entity, Prop_Data, "m_iName")) GetEntPropString(entity, Prop_Data, "m_iName", szName, sizeof(szName));
						int iRemake = CreateEntityByName("prop_physics");
						if (IsValidEntity(iRemake))
						{
							AcceptEntityInput(entity,"kill");
							DispatchKeyValue(iRemake, "OverrideScript", "mass,35");
							DispatchKeyValue(iRemake, "model", szModel);
							DispatchKeyValue(iRemake, "spawnflags", szSF);
							DispatchKeyValue(iRemake, "skin", szSkin);
							DispatchKeyValue(iRemake, "body", szBody);
							DispatchKeyValue(iRemake, "targetname", szName);
							TeleportEntity(iRemake, vecOrigin, vecAngles, NULL_VECTOR);
							DispatchSpawn(iRemake);
							ActivateEntity(iRemake);
						}
					}
				}
			}
		}
	}
}

public void PortalPlaced(const char[] output, int caller, int activator, float delay)
{
	// Activator is portalgun
	if ((IsValidEntity(activator)) && (IsValidEntity(caller)))
	{
		// Do not check placed portal 2s
		if (HasEntProp(caller, Prop_Data, "m_bIsPortal2"))
		{
			if (GetEntProp(caller, Prop_Data, "m_bIsPortal2")) return;
			if ((HasEntProp(activator, Prop_Data, "m_hOwner")) && (HasEntProp(activator, Prop_Data, "m_bCanFirePortal2")))
			{
				// Only apply to portalguns that cannot fire portal 2
				if (!GetEntProp(activator, Prop_Data, "m_bCanFirePortal2"))
				{
					int client = GetEntPropEnt(activator, Prop_Data, "m_hOwner");
					if ((IsValidEntity(client)) && (client > 0) && (client < MaxClients+1))
					{
						int ent = -1;
						while((ent = FindEntityByClassname(ent, "prop_portal")) != INVALID_ENT_REFERENCE)
						{
							if (IsValidEntity(ent))
							{
								if (ent != caller)
								{
									if (HasEntProp(ent, Prop_Data, "m_bActivated"))
									{
										if (GetEntProp(ent, Prop_Data, "m_bActivated"))
										{
											if (GetEntProp(ent, Prop_Data, "m_bIsPortal2"))
											{
												if ((HasEntProp(ent, Prop_Data, "m_iLinkageGroupID")) && (HasEntProp(ent, Prop_Data, "m_hLinkedPortal")))
												{
													if ((GetEntPropEnt(ent, Prop_Data, "m_hLinkedPortal") == -1) && (!GetEntProp(ent, Prop_Data, "m_iLinkageGroupID")))
													{
														SetEntPropEnt(ent, Prop_Data, "m_hLinkedPortal", caller);
														SetEntPropEnt(caller, Prop_Data, "m_hLinkedPortal", ent);
														//SetEntProp(caller, Prop_Data, "m_iLinkageGroupID", 0);
													}
												}
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
	return;
}

public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if ((client > 0) && (client < MaxClients+1))
	{
		CreateTimer(0.1, clspawnpost, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Event_EntityKilled(Handle event, const char[] name, bool Broadcast)
{
	int killed = GetEventInt(event, "entindex_killed");
	if (IsValidEntity(killed))
	{
		if ((killed > 0) && (killed < MaxClients+1))
		{
			if (WeapList == -1) WeapList = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
			if (WeapList != -1)
			{
				char clschk[32];
				for (int l; l<104; l += 4)
				{
					int tmpi = GetEntDataEnt2(killed, WeapList + l);
					if ((tmpi != 0) && (IsValidEntity(tmpi)))
					{
						GetEntityClassname(tmpi, clschk, sizeof(clschk));
						if (StrContains(clschk, "tf_weapon_portalgun", false) != -1)
						{
							SetEntProp(tmpi, Prop_Data, "m_fEffects", 129);
							break;
						}
					}
				}
			}
		}
	}
}

public Action clspawnpost(Handle timer, int client)
{
	if (IsValidEntity(client) && IsPlayerAlive(client))
	{
		SDKHookEx(client, SDKHook_WeaponSwitch, OnWeaponUse);
	}
	else if (IsClientConnected(client))
	{
		CreateTimer(0.5, clspawnpost, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action OnWeaponUse(int client, int weapon)
{
	if ((IsValidEntity(client)) && (IsValidEntity(weapon)))
	{
		char szCls[32];
		GetEntPropString(weapon, Prop_Data, "m_iClassname", szCls, sizeof(szCls));
		if (StrContains(szCls, "tf_weapon_portalgun", false) != -1)
		{
			// Fixes weapon holding position
			SetVariantString("anim_attachment_RH");
			AcceptEntityInput(weapon, "SetParentAttachment");
			SetEntProp(weapon, Prop_Data, "m_fEffects", 16);
			float vecOffs[3];
			vecOffs[0] = -5.0;
			SetEntPropVector(weapon, Prop_Data, "m_vecOrigin", vecOffs);
			vecOffs[0] = 0.0;
			vecOffs[1] = 180.0;
			SetEntPropVector(weapon, Prop_Data, "m_angRotation", vecOffs);
			
			if (HasEntProp(weapon, Prop_Data, "m_bCanFirePortal1"))
			{
				// Need to ensure can fire portal 2 when on later levels, and not be able to on early levels
				if ((HasPickedUpPortal2) || (StrEqual(szMap, "testchmb_a_08", false)) || (StrEqual(szMap, "testchmb_a_09", false)) || (StrContains(szMap, "testchmb_a_1", false) == 0))
				{
					SetEntProp(weapon, Prop_Data, "m_bCanFirePortal1", 1);
					SetEntProp(weapon, Prop_Data, "m_bCanFirePortal2", 1);
				}
				else
				{
					SetEntProp(weapon, Prop_Data, "m_bCanFirePortal1", 1);
					SetEntProp(weapon, Prop_Data, "m_bCanFirePortal2", 0);
				}
			}
		}
	}
}

public Action DropPortalGun(int client, int args)
{
	if (IsValidEntity(client))
	{
		if (HasEntProp(client, Prop_Data, "m_hActiveWeapon"))
		{
			int ent = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
			if (IsValidEntity(ent))
			{
				char szCls[32];
				GetEntPropString(ent, Prop_Data, "m_iClassname", szCls, sizeof(szCls));
				if (StrContains(szCls, "tf_weapon_portalgun", false) != -1)
				{
					SetEntProp(ent, Prop_Data, "m_fEffects", 129);
				}
			}
		}
	}
	return Plugin_Continue;
}

public void TouchPortalGunOutput(const char[] output, int caller, int activator, float delay)
{
	if ((IsValidEntity(caller)) && (activator > 0) && (activator < MaxClients+1))
	{
		UnhookSingleEntityOutput(caller, output, TouchPortalGunOutput);
		CheckTouchPortalgun(caller, activator);
	}
}

public Action StartTouchPortalGun(int entity, int other)
{
	if (IsValidEntity(entity))
	{
		if ((other < MaxClients+1) && (other > 0))
		{
			UnhookSingleEntityOutput(entity, "OnPlayerUse", TouchPortalGunOutput);
			UnhookSingleEntityOutput(entity, "OnPlayerPickup", TouchPortalGunOutput);
			SDKUnhook(entity, SDKHook_StartTouch, StartTouchPortalGun);
			CheckTouchPortalgun(entity, other);
		}
	}
}

void CheckTouchPortalgun(int entity, int client)
{
	if ((IsValidEntity(entity)) && (IsValidEntity(client)))
	{
		if (HasEntProp(entity, Prop_Data, "m_bCanFirePortal1"))
		{
			// Fixes issue of picking up the second portal gun upgrade which can fire portal 2 but cannot fire 1
			if (GetEntProp(entity, Prop_Data, "m_bCanFirePortal2"))
			{
				if (!GetEntProp(entity, Prop_Data, "m_bCanFirePortal1")) SetEntProp(entity, Prop_Data, "m_bCanFirePortal1", 1);
				HasPickedUpPortal2 = true;
				int ent = -1;
				while((ent = FindEntityByClassname(ent, "tf_weapon_portalgun")) != INVALID_ENT_REFERENCE)
				{
					if (IsValidEntity(ent))
					{
						if (HasEntProp(ent, Prop_Data, "m_bCanFirePortal2"))
						{
							SetEntProp(ent, Prop_Data, "m_bCanFirePortal2", 1);
						}
					}
				}
			}
			if (WeapList == -1) WeapList = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
			if (WeapList != -1)
			{
				char clschk[32];
				for (int l; l<104; l += 4)
				{
					int tmpi = GetEntDataEnt2(client, WeapList + l);
					if ((tmpi != 0) && (IsValidEntity(tmpi)) && (tmpi != entity))
					{
						GetEntityClassname(tmpi, clschk, sizeof(clschk));
						if (StrEqual(clschk, "tf_weapon_portalgun", false))
						{
							// Remove currently equipped portal gun so the one being picked up fires its OnPlayerPickup outputs
							AcceptEntityInput(tmpi, "kill");
							break;
						}
					}
				}
			}
		}
	}
}

public Action SoundFixesNormal(int clients[64], int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags)
{
	if (flSoundChecksSkip >= GetTickedTime()) return Plugin_Continue;
	
	// Change fall damage sound to Portal land sound if using Portal gun.
	static char szClassname[32];
	if (StrContains(sample, "pl_fallpain", false) != -1)
	{
		if ((entity > 0) && (entity <= MaxClients))
		{
			if (HasEntProp(entity, Prop_Data, "m_hActiveWeapon"))
			{
				int hActiveWeapon = GetEntPropEnt(entity, Prop_Data, "m_hActiveWeapon");
				if (IsValidEntity(hActiveWeapon))
				{
					GetEntityClassname(hActiveWeapon, szClassname, sizeof(szClassname));
					if (StrContains(szClassname, "weapon_portalgun", false) != -1)
					{
						Format(sample, sizeof(sample), "sound/player/futureshoes%i.wav", GetRandomInt(1,2));
						
						return Plugin_Changed;
					}
				}
			}
		}
	}
	
	return Plugin_Continue;
}