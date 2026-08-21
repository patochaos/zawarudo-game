extends RefCounted
class_name Phase

## Loop states, in their own script so GameManager, UI and PreviewLayer can all
## reference them as real constants without a cyclic preload.

enum { PLANNING, COMMITTING, EXECUTING, GAME_OVER, MENU, FREEPLAY, ONLINE_LOBBY, ONLINE_WAIT, REPLAY,
	CHARACTER_SELECT, TEAM_SELECT }
