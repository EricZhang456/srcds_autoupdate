#include <sourcemod>
#include <dhooks>

#define BASE_STR_LEN 128
#define DEFAULT_FILE_PATH "data/srcds_autoupdate/"

Address steamServer;
Handle steamServerSdkCall;
DHookSetup restartRequestedHook;

ConVar cvarAction;
ConVar cvarFilePath;
ConVar cvarCountdown;
ConVar cvarCustomMessage;

public Plugin myinfo = {
    name = "SRCDS Auto Update",
    author = "Eric Zhang",
    description = "Automatically updates SRCDS.",
    version = "1.0",
    url = "https://ericaftereric.top/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    if (!IsDedicatedServer()) {
        strcopy(error, err_max, "This plugin must be run under a dedicated server.")
        return APLRes_SilentFailure;
    }
    return APLRes_Success;
}

public void OnPluginStart() {
    LoadTranslations("srcds_autoupdate.phrases");

    cvarAction = CreateConVar("sm_srcds_autoupdate_action", "1", "What to do when a new update is received?\n"
    ... "0: Do nothing\n"
    ... "1: Run \"_restart\", you might want to set up -autoupdate, see https://developer.valvesoftware.com/wiki/Restart\n"
    ... "2: Creates a file, see sm_srcds_autoupdate_file_path for more details", _, true, 0.0, true, 2.0);
    cvarFilePath = CreateConVar("sm_srcds_autoupdate_file_path", DEFAULT_FILE_PATH,
        "Where to create the file? Paths are relative to the SourceMod root directory (usually addons/sourcemod). "
        ... "Filename will be srcds_autoupdate_<game dir name>_<date + time>.");
    cvarCountdown = CreateConVar("sm_srcds_autoupdate_countdown", "15", "How long in seconds will the plugin wait before the action is taken when a new update is released.");
    cvarCustomMessage = CreateConVar("sm_srcds_autoupdate_message", "", "A custom message to print in chat when an update is released instead of the default message.");

    cvarFilePath.AddChangeHook(OnFilePathCvarChanged);

#if defined DEBUG
    RegAdminCmd("sm_srcds_autoupdate_test", OnTestCommand, ADMFLAG_ROOT, "Test autoupdate");
#endif

    GameData config = new GameData("srcds_autoupdate");
    if (!config) {
        delete config;
        SetFailState("Failed to load gamedata.");
        return;
    }

    restartRequestedHook = DHookCreateFromConf(config, "ISteamGameServer::WasRestartRequested");
    if (!restartRequestedHook) {
        SetFailState("Failed to create virtual hook for ISteamGameServer::WasRestartRequested");
    }

    StartPrepSDKCall(SDKCall_Static);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "Steam3Server");
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    steamServerSdkCall = EndPrepSDKCall();
    if (!steamServerSdkCall) {
        steamServer = GameConfGetAddress(config, "s_Steam3Server");
        if (!steamServer) {
            SetFailState("Failed to get Steam3Server instance");
        }
    } else {
        steamServer = SDKCall(steamServerSdkCall);
    }

    DHookRaw(restartRequestedHook, true, GetSteamServer(), _, OnRestartRequested);

    delete config;

    AutoExecConfig();
}

public void OnFilePathCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (newValue[0] == '/' || (newValue[1] == ':' && newValue[2] == '\\')) {
        PrintToServer("File path must be relative, resetting sm_srcds_autoupdate_file_path to %s", DEFAULT_FILE_PATH);
        cvarFilePath.SetString(DEFAULT_FILE_PATH);
    }
}

void RunUpdateAction() {
    if (GetClientCount() == 0) {
        OnUpdateAction();
        return;
    }
    char customMessage[BASE_STR_LEN];
    cvarCustomMessage.GetString(customMessage, sizeof(customMessage));
    if (strlen(customMessage)) {
        PrintToChatAll(customMessage);
    } else {
        PrintToChatAll("%t", "SRCDS_AUTOUPDATE_MESSAGE", cvarCountdown.IntValue);
    }
    CreateTimer(cvarCountdown.FloatValue, OnUpdateActionTimerEnd);
}

public void OnUpdateActionTimerEnd(Handle timer) {
    OnUpdateAction();
}

void OnUpdateAction() {
    switch (cvarAction.IntValue) {
        case 1: {
            ServerCommand("_restart");
        }
        case 2: {
            char fileName[PLATFORM_MAX_PATH], filePath[PLATFORM_MAX_PATH], basePath[PLATFORM_MAX_PATH];
            cvarFilePath.GetString(basePath, sizeof(basePath));
            GetUpdateFileName(fileName, sizeof(fileName));
            BuildPath(Path_SM, filePath, sizeof(filePath), "%s/%s", basePath, fileName);
            File file = OpenFile(filePath, "w");
            delete file;
        }
        default: {
            return;
        }
    }
}

public MRESReturn OnRestartRequested(Address pThis, DHookReturn hReturn) {
    RunUpdateAction();
    return MRES_Ignored;
}

#if defined DEBUG
public Action OnTestCommand(int client, int args) {
    RunUpdateAction();
    return Plugin_Continue;
}
#endif

int GetUpdateFileName(char[] dest, int len) {
    char gameDir[PLATFORM_MAX_PATH], timeStr[BASE_STR_LEN];
    GetGameFolderName(gameDir, sizeof(gameDir));
    FormatTime(timeStr, sizeof(timeStr), "%Y-%m-%dT%H:%M:%SZ");
    return Format(dest, len, "srcds_autoupdate_%s_%s", gameDir, timeStr);
}

Address GetSteamServer() {
    return view_as<Address>(LoadFromAddress(steamServer + view_as<Address>(0x04), NumberType_Int32));
}
