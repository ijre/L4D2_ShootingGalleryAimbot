#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#define DEFAULT_DEBUG 0
#tryinclude <SetupDebugMacros.sp>
#tryinclude <PrintToChatAllLog.sp>

public Plugin myinfo =
{
  name = "Shooting Gallery Aimbot",
  author = "ijre",
  version = "1.2.0"
}

#define FloatVecToPrintable(%1) %1[0], %1[1], %1[2]

static int MusicLoopIndex;

#define PEANUT 0
#define MOUSTACHIO 1
#define TARGETS_TOTAL 8
#define PROP_INDEX 0
#define ROTATOR_INDEX 1

static int TargetIndices[TARGETS_TOTAL][2];

static ConVar SilentAim;
static ConVar AvoidPeanut;

public void OnMapStart()
{
  SilentAim = CreateConVar("sm_galleryaimbot_silentaim", "1", "Whether or not the aimbot snaps the player's viewangles to the target (1 for no)", FCVAR_NOTIFY);
  AvoidPeanut = CreateConVar("sm_galleryaimbot_avoid_peanut", "1", "Whether or not to avoid shooting a target if Peanut would be hit. (0 to shoot anyway)", FCVAR_NOTIFY);

#if DEBUG
  RegAdminCmd("sm_dumpents", dumpents, ADMFLAG_ROOT);
#endif

  char map[192];
  GetCurrentMap(map, sizeof(map));
  if (!!strncmp(map, "c2m2", 4))
  {
    // doing this instead of AskPluginLoad2 because APLRes_SilentFailure still appends to/creates error logs
    LogMessage("Incorrect map, stopping plugin.");

    char name[192];
    GetPluginFilename(INVALID_HANDLE, name, sizeof(name));
    ServerCommand("sm plugins unload %s", name);
  }

  HookEvent("round_freeze_end", OnRoundStart);
  HookEvent("mission_lost", OnFailure);

  FindTargetIndicies();

  AutoExecConfig(true, "ShootingGalleryAimbot");
}

#if DEBUG
Action dumpents(int client, int args)
{
  PrintToChatAllLog("\nMUSIC LOOP: %d", MusicLoopIndex);
  PrintToChatAllLog("PEANUT: %d ~~ %d", TargetIndices[PEANUT][PROP_INDEX], TargetIndices[PEANUT][ROTATOR_INDEX]);
  PrintToChatAllLog("MOUSTACHIO: %d ~~ %d", TargetIndices[MOUSTACHIO][PROP_INDEX], TargetIndices[MOUSTACHIO][ROTATOR_INDEX]);

  for (int targ = MOUSTACHIO + 1; targ < TARGETS_TOTAL; targ++)
  {
    PrintToChatAllLog("SKELE %d: %d ~~ %d", targ - 1, TargetIndices[targ][PROP_INDEX], TargetIndices[targ][ROTATOR_INDEX]);
  }

  return Plugin_Handled;
}
#endif

void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
  FindTargetIndicies();
}

void OnFailure(Event event, const char[] name, bool dontBroadcast)
{
  MusicLoopIndex = 0;

  for (int targ = 0; targ < TARGETS_TOTAL; targ++)
  {
    TargetIndices[targ][PROP_INDEX] = 0;
    TargetIndices[targ][ROTATOR_INDEX] = 0;
  }
}

static void FindTargetIndicies()
{
  int ent = -1;
  while ((ent = FindEntityByClassname(ent, "ambient_generic")) != -1)
  {
    char name[25];
    GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));

    if (!strncmp(name, "gallery_operating_sound", 23))
    {
      MusicLoopIndex = ent;
      break;
    }
  }

  ent = -1;
  while ((ent = FindEntityByClassname(ent, "prop_dynamic")) != -1)
  {
    char model[55];
    GetEntPropString(ent, Prop_Data, "m_ModelName", model, sizeof(model));
    if (StrContains(model, "gallery_target") == -1)
    {
      continue;
    }

    if (StrContains(model, "lilpeanut.mdl") != -1)
    {
      TargetIndices[PEANUT][PROP_INDEX] = ent;
    }
    else if (StrContains(model, "moustachio.mdl") != -1)
    {
      TargetIndices[MOUSTACHIO][PROP_INDEX] = ent;
    }
    else if (StrContains(model, "skeleton.mdl") != -1)
    {
      static int skeleDex = MOUSTACHIO + 1;

      if (skeleDex == TARGETS_TOTAL)
      {
        skeleDex = MOUSTACHIO + 1;
      }

      TargetIndices[skeleDex++][PROP_INDEX] = ent;
    }
  }

  ent = -1;
  while ((ent = FindEntityByClassname(ent, "func_rot_button")) != -1)
  {
    char targetName[25];
    GetEntPropString(ent, Prop_Data, "m_iName", targetName, sizeof(targetName));

    if (!strncmp(targetName, "peanut_target_1_rotator", 23))
    {
      TargetIndices[PEANUT][ROTATOR_INDEX] = ent;
    }
    else if (!strncmp(targetName, "green_target_1_rotator", 22))
    {
      TargetIndices[MOUSTACHIO][ROTATOR_INDEX] = ent;
    }
    else
    {
      for (int i = 1; i <= 3; i++)
      {
        char galleryTarget[192] = "_target_%d_rotator";
        Format(galleryTarget, sizeof(galleryTarget), galleryTarget, i);

        if (StrContains(targetName, galleryTarget) == -1)
        {
          continue;
        }

        ReplaceString(galleryTarget, sizeof(galleryTarget), "_rotator", "");

        for (int target = MOUSTACHIO + 1; target < TARGETS_TOTAL; target++)
        {
          GetEntPropString(TargetIndices[target][PROP_INDEX], Prop_Data, "m_iName", targetName, sizeof(targetName));
          if (StrContains(targetName, galleryTarget) != -1 && !TargetIndices[target][ROTATOR_INDEX])
          {
            TargetIndices[target][ROTATOR_INDEX] = ent;
            break;
          }
        }
      }
    }
  }
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float cmdAngs[3])
{
  if (!IsClientConnected(client) || !IsPlayerAlive(client) || IsFakeClient(client) || GetClientTeam(client) != 2)
  {
    return Plugin_Continue;
  }

  if (!MusicLoopIndex || !GetEntProp(MusicLoopIndex, Prop_Data, "m_fActive")) // John Valve invents world's first Foolean value
  {
    return Plugin_Continue;
  }

  int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
  char cName[20];
  GetEntityClassname(wep, cName, sizeof(cName));

  if (wep == -1 || (wep != GetPlayerWeaponSlot(client, 0) && wep != GetPlayerWeaponSlot(client, 1))
      || !strncmp(cName[7], "melee", 5) || !strncmp(cName[7], "chainsaw", 8)
      || GetEntPropFloat(wep, Prop_Send, "m_flNextPrimaryAttack") > GetGameTime())
  {
    return Plugin_Continue;
  }

  float eyePos[3];
  GetClientEyePosition(client, eyePos);

  for (int i = PEANUT + 1; i < TARGETS_TOTAL; i++)
  {
    float targetPos[3];
    float targetRotatorRot[3];
    GetCenterOfEntity(TargetIndices[i][PROP_INDEX], targetPos);
    GetEntPropVector(TargetIndices[i][ROTATOR_INDEX], Prop_Send, "m_angRotation", targetRotatorRot);

    // the gallery has object pooling for inactive targets setup underneath the map, and an x rot of 0.0 means they're standing up
    if (targetPos[2] < 0.0 || targetRotatorRot[0] != 0.0)
    {
      continue;
    }

    float newAngs[3];
    MakeVectorFromPoints(eyePos, targetPos, newAngs);
    GetVectorAngles(newAngs, newAngs);

    TR_TraceRayFilter(eyePos, newAngs, MASK_SHOT, RayType_Infinite, CheckForLOS, TargetIndices[i][PROP_INDEX]);

    if (TR_GetEntityIndex() != TargetIndices[i][PROP_INDEX])
    {
      continue;
    }

    cmdAngs = newAngs;

    if (!SilentAim.BoolValue)
    {
      TeleportEntity(client, NULL_VECTOR, cmdAngs, NULL_VECTOR);
    }

    buttons |= IN_ATTACK;

    return Plugin_Changed;
  }

  return Plugin_Continue;
}

// #region Helpers
// #region Filters
stock bool CheckForLOS(int ent, int mask, int target)
{
  if (ent != target)
  {
    return false;
  }

  if (AvoidPeanut.BoolValue)
  {
    Handle extraTrace = TR_ClipCurrentRayToEntityEx(MASK_SHOT, TargetIndices[PEANUT][PROP_INDEX]);

    if (TR_DidHit(extraTrace))
    {
      delete extraTrace;
      return false;
    }

    delete extraTrace;
  }

  return true;
}
// #endregion

stock void GetCenterOfEntity(int ent, float output[3])
{
  GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", output);

  float temp[2][3];
  GetEntPropVector(ent, Prop_Send, "m_vecMins", temp[0]);
  GetEntPropVector(ent, Prop_Send, "m_vecMaxs", temp[1]);

  output[0] += (temp[0][0] + temp[1][0]) * 0.5;
  output[1] += (temp[0][1] + temp[1][1]) * 0.5;
  output[2] += (temp[0][2] + temp[1][2]) * 0.5;
}
// #endregion