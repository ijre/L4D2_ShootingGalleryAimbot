#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <left4dhooks>
// #include "C:/Users/User1/source/repos/# shared notes tf2-l4d2/PrintToChatAllLog.sp"

public Plugin myinfo =
{
  name = "Shooting Gallery Aimbot",
  author = "ijre",
  version = "1.0.1"
}

#define FloatVecToPrintable(%1) %1[0], %1[1], %1[2]

static int UseButtonIndex;

#define PEANUT 0
#define MOUSTACHIO 1
#define TARGETS_TOTAL 8
#define PROP_INDEX 0
#define ROTATOR_INDEX 1

static int TargetIndices[TARGETS_TOTAL][2];

ConVar SilentAim;

public void OnMapStart()
{
  SilentAim = CreateConVar("sm_galleryaimbot_silentaim", "1", "Whether or not the aimbot snaps the player's viewangles to the target (1 for no)", FCVAR_NOTIFY);

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

  int ent = -1;
  while ((ent = FindEntityByClassname(ent, "func_button")) != -1)
  {
    char name[192];
    GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));

    if (!strncmp(name, "shootinggame_start_button", 25))
    {
      UseButtonIndex = ent;
      break;
    }
  }

  ent = -1;
  while ((ent = FindEntityByClassname(ent, "prop_dynamic")) != -1)
  {
    char model[192];
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
      TargetIndices[skeleDex++][PROP_INDEX] = ent;
    }
  }

  ent = -1;
  while ((ent = FindEntityByClassname(ent, "func_rot_button")) != -1)
  {
    char targetName[192];
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
  if (!IsClientConnected(client) || !IsPlayerAlive(client) || IsFakeClient(client) || L4D_GetClientTeam(client) != L4DTeam_Survivor)
  {
    return Plugin_Continue;
  }

  if (!IsValidEntity(UseButtonIndex))
  {
    char invalidEnts[192];
    invalidEnts = "Invalid ents at %d (UseButtonIndex)";

    for (int i = 0; i < TARGETS_TOTAL; i++)
    {
      if (IsValidEntity(TargetIndices[i][PROP_INDEX]))
      {
        continue;
      }

      char invalidEntTargets[192];
      Format(invalidEntTargets, sizeof(invalidEntTargets), ", %d (TargetIndices[%d][PROP_INDEX])", TargetIndices[i][PROP_INDEX], i);
      StrCat(invalidEnts, sizeof(invalidEnts), invalidEntTargets);
    }

    ThrowError(invalidEnts, UseButtonIndex);
  }

  if (!GetEntProp(UseButtonIndex, Prop_Data, "m_bLocked")) // unlocked means the game hasn't started
  {
    return Plugin_Continue;
  }

  int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
  if (wep == -1 || (wep != GetPlayerWeaponSlot(client, 0) && wep != GetPlayerWeaponSlot(client, 1)) || L4D2_GetWeaponId(wep) == L4D2WeaponId_Melee
      || GetEntPropFloat(wep, Prop_Send, "m_flNextPrimaryAttack") > GetGameTime())
  {
    return Plugin_Continue;
  }

  float eyePos[3];
  GetClientEyePosition(client, eyePos);

  for (int i = 1; i < TARGETS_TOTAL; i++)
  {
    float targetPos[3];
    float targetRotatorRot[3];
    GetAbsOrigin(TargetIndices[i][PROP_INDEX], targetPos, true);
    GetEntPropVector(TargetIndices[i][ROTATOR_INDEX], Prop_Send, "m_angRotation", targetRotatorRot);

    // the gallery has object pooling for inactive targets setup underneath the map, and an x rot of 0.0 means they're standing up
    if (targetPos[2] < 0.0 || targetRotatorRot[0] != 0.0)
    {
      continue;
    }

    float newAngs[3];
    MakeVectorFromPoints(eyePos, targetPos, newAngs);
    GetVectorAngles(newAngs, newAngs);

    TR_TraceRayFilter(eyePos, newAngs, CONTENTS_SOLID, RayType_Infinite, CheckForLOS, TargetIndices[i][PROP_INDEX]);
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

bool CheckForLOS(int ent, int mask, int target)
{
  return ent == target;
}